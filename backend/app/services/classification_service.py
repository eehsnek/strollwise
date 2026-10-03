"""Classifies a single H3 cell aggregate by behavior + function."""
from __future__ import annotations

from collections.abc import Mapping

from app.models.enums import BehaviorType, FunctionType
from app.models.h3_cell_aggregate import H3CellAggregate
from app.services.aggregation_service_tag_buckets import (
    COMMERCIAL_TAGS,
    FOOD_TAGS,
    NIGHTLIFE_TAGS,
    RESIDENTIAL_TAGS,
    SAFETY_TAGS,
    STUDENT_TAGS,
    TRANSPORT_TAGS,
)

LOCAL_BEHAVIOR_THRESHOLD = 0.70
TOURIST_BEHAVIOR_THRESHOLD = 0.70
MIN_REPORTS_FOR_CLASSIFICATION = 3


class ClassificationService:
    @staticmethod
    def behavior_type(cell: H3CellAggregate) -> str:
        total = max(cell.report_count, 0)
        if total == 0:
            return BehaviorType.MIXED_AREA.value
        local_ratio = cell.local_count / total if total else 0
        intl_ratio = cell.international_count / total if total else 0
        if local_ratio >= LOCAL_BEHAVIOR_THRESHOLD:
            return BehaviorType.LOCAL_AREA.value
        if intl_ratio >= TOURIST_BEHAVIOR_THRESHOLD:
            return BehaviorType.TOURIST_AREA.value
        return BehaviorType.MIXED_AREA.value

    @staticmethod
    def function_type(cell: H3CellAggregate) -> str:
        if cell.report_count < MIN_REPORTS_FOR_CLASSIFICATION:
            return FunctionType.EMERGING_ZONE.value

        tag_counts: Mapping[str, int] = cell.tag_counts_json or {}
        category_counts: Mapping[str, int] = cell.category_counts_json or {}

        def score(keywords: set[str]) -> int:
            return sum(
                count
                for tag, count in tag_counts.items()
                if tag.lower() in keywords
            )

        food_score = score(FOOD_TAGS) + category_counts.get("food", 0) * 2
        student_score = score(STUDENT_TAGS) + category_counts.get("school", 0) * 2
        transport_score = score(TRANSPORT_TAGS) + category_counts.get("transport", 0) * 2
        commercial_score = score(COMMERCIAL_TAGS) + category_counts.get("shopping", 0) * 2
        residential_score = score(RESIDENTIAL_TAGS)
        safety_score = score(SAFETY_TAGS) + category_counts.get("safety", 0) * 3 + category_counts.get("issue", 0) * 2
        nightlife_score = score(NIGHTLIFE_TAGS) + category_counts.get("nightlife", 0) * 2

        scores: dict[str, int] = {
            FunctionType.FOOD_HOTSPOT.value: food_score,
            FunctionType.STUDENT_AREA.value: student_score,
            FunctionType.TRANSPORT_ZONE.value: transport_score,
            FunctionType.COMMERCIAL_ZONE.value: commercial_score,
            FunctionType.RESIDENTIAL_ZONE.value: residential_score,
            FunctionType.SAFETY_CONCERN.value: safety_score,
        }
        # Nightlife rolls into commercial/busy unless it is by far the strongest signal.
        if nightlife_score > 0:
            scores[FunctionType.BUSY_ZONE.value] = nightlife_score

        dominant = max(scores.items(), key=lambda kv: kv[1])
        if dominant[1] == 0:
            # Tourist areas with lots of activity but no specific signal become tourist hotspots.
            if cell.behavior_type == BehaviorType.TOURIST_AREA.value and cell.report_count >= 6:
                return FunctionType.TOURIST_HOTSPOT.value
            if cell.report_count >= 12:
                return FunctionType.BUSY_ZONE.value
            return FunctionType.UNKNOWN.value
        return dominant[0]

    @classmethod
    def apply(cls, cell: H3CellAggregate) -> H3CellAggregate:
        cell.behavior_type = cls.behavior_type(cell)
        cell.function_type = cls.function_type(cell)
        return cell

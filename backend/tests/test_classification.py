from __future__ import annotations

from app.models.enums import BehaviorType, FunctionType
from app.models.h3_cell_aggregate import H3CellAggregate
from app.services.classification_service import ClassificationService


def _cell(**overrides) -> H3CellAggregate:
    base = dict(
        h3_index="8a1234567",
        resolution=8,
        report_count=10,
        local_count=0,
        international_count=0,
        mixed_score=0.0,
        category_counts_json={},
        tag_counts_json={},
        dominant_category=None,
        dominant_tags_json=[],
        behavior_type="mixed_area",
        function_type="unknown",
        crowd_score=0.0,
        popularity_score=0.0,
        confidence_score=0.0,
        time_distribution_json={},
        peak_hours_json=[],
    )
    base.update(overrides)
    return H3CellAggregate(**base)


def test_behavior_type_local_when_majority_local():
    cell = _cell(report_count=10, local_count=8, international_count=2)
    assert ClassificationService.behavior_type(cell) == BehaviorType.LOCAL_AREA.value


def test_behavior_type_tourist_when_majority_international():
    cell = _cell(report_count=10, local_count=1, international_count=9)
    assert ClassificationService.behavior_type(cell) == BehaviorType.TOURIST_AREA.value


def test_behavior_type_mixed_otherwise():
    cell = _cell(report_count=10, local_count=5, international_count=5)
    assert ClassificationService.behavior_type(cell) == BehaviorType.MIXED_AREA.value


def test_function_type_food_hotspot():
    cell = _cell(
        report_count=8,
        tag_counts_json={"food": 3, "cafe": 2, "restaurant": 2},
        category_counts_json={"food": 5},
    )
    assert ClassificationService.function_type(cell) == FunctionType.FOOD_HOTSPOT.value


def test_function_type_student_area():
    cell = _cell(
        report_count=6,
        tag_counts_json={"student": 3, "university": 2, "library": 1},
        category_counts_json={"school": 4},
    )
    assert ClassificationService.function_type(cell) == FunctionType.STUDENT_AREA.value


def test_function_type_safety_concern_prioritized():
    cell = _cell(
        report_count=5,
        tag_counts_json={"theft": 3, "food": 1},
        category_counts_json={"safety": 3, "food": 1},
    )
    assert ClassificationService.function_type(cell) == FunctionType.SAFETY_CONCERN.value


def test_function_type_emerging_when_few_reports():
    cell = _cell(report_count=1)
    assert ClassificationService.function_type(cell) == FunctionType.EMERGING_ZONE.value


def test_apply_sets_both_classifications():
    cell = _cell(
        report_count=10,
        local_count=8,
        international_count=2,
        tag_counts_json={"cafe": 4, "food": 4},
        category_counts_json={"food": 6},
    )
    ClassificationService.apply(cell)
    assert cell.behavior_type == BehaviorType.LOCAL_AREA.value
    assert cell.function_type == FunctionType.FOOD_HOTSPOT.value

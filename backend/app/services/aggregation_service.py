"""Recomputes H3 cell aggregates from raw reports."""
from __future__ import annotations

from collections import Counter
from collections.abc import Iterable
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.core.config import settings
from app.models.h3_cell_aggregate import H3CellAggregate
from app.models.report import Report
from app.repositories.h3_repository import H3Repository
from app.repositories.report_repository import ReportRepository
from app.services.classification_service import ClassificationService
from app.utils.time_utils import as_utc_aware, hour_of
from app.utils.user_type_utils import report_counts_local_international


class AggregationService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.h3_repo = H3Repository(db)
        self.report_repo = ReportRepository(db)

    def recompute_cell(self, h3_index: str) -> H3CellAggregate:
        reports = self.report_repo.list_by_h3_indexes([h3_index])
        if not reports:
            cell = self.h3_repo.get(h3_index)
            if cell is not None:
                cell.report_count = 0
                cell.behavior_type = "mixed_area"
                cell.function_type = "emerging_zone"
                cell.confidence_score = 0
                self.h3_repo.upsert(cell)
            return cell or self._empty_cell(h3_index)
        cell = self._aggregate(h3_index, reports)
        ClassificationService.apply(cell)
        return self.h3_repo.upsert(cell)

    def recompute_cells(self, h3_indexes: Iterable[str]) -> list[H3CellAggregate]:
        return [self.recompute_cell(idx) for idx in h3_indexes]

    # --- internal helpers -------------------------------------------------

    def _empty_cell(self, h3_index: str) -> H3CellAggregate:
        return H3CellAggregate(
            h3_index=h3_index,
            resolution=settings.h3_resolution,
            report_count=0,
            behavior_type="mixed_area",
            function_type="emerging_zone",
        )

    def _aggregate(self, h3_index: str, reports: list[Report]) -> H3CellAggregate:
        category_counts = self.build_category_counts(reports)
        tag_counts = self.build_tag_counts(reports)

        local_count = sum(
            1 for r in reports if report_counts_local_international(r)[0]
        )
        intl_count = sum(
            1 for r in reports if report_counts_local_international(r)[1]
        )
        total = len(reports)
        mixed_score = 0.0
        if total:
            mixed_score = 1.0 - abs(local_count - intl_count) / total

        dominant_category = None
        if category_counts:
            dominant_category = max(category_counts.items(), key=lambda kv: kv[1])[0]
        dominant_tags = [t for t, _ in tag_counts.most_common(5)]

        time_distribution = self.compute_time_distribution(reports)
        peak_hours = self.compute_peak_hours(time_distribution)
        crowd_score = self.compute_crowd_score(reports)
        popularity_score = self.compute_popularity_score(reports)
        confidence_score = self.compute_confidence_score(reports)

        last_report_at = max((r.created_at for r in reports), default=None)

        existing = self.h3_repo.get(h3_index)
        cell = existing or H3CellAggregate(h3_index=h3_index)
        cell.resolution = settings.h3_resolution
        cell.report_count = total
        cell.local_count = local_count
        cell.international_count = intl_count
        cell.mixed_score = float(mixed_score)
        cell.category_counts_json = dict(category_counts)
        cell.tag_counts_json = dict(tag_counts)
        cell.dominant_category = dominant_category
        cell.dominant_tags_json = dominant_tags
        cell.crowd_score = float(crowd_score)
        cell.popularity_score = float(popularity_score)
        cell.confidence_score = float(confidence_score)
        cell.time_distribution_json = time_distribution
        cell.peak_hours_json = peak_hours
        cell.last_report_at = last_report_at
        return cell

    # --- public helpers (exposed for tests) ------------------------------

    @staticmethod
    def build_category_counts(reports: Iterable[Report]) -> Counter[str]:
        c: Counter[str] = Counter()
        for r in reports:
            if r.category:
                c[r.category.lower()] += 1
        return c

    @staticmethod
    def build_tag_counts(reports: Iterable[Report]) -> Counter[str]:
        c: Counter[str] = Counter()
        for r in reports:
            for tag in r.tags_json or []:
                c[str(tag).lower()] += 1
        return c

    @staticmethod
    def compute_time_distribution(reports: Iterable[Report]) -> dict[str, int]:
        distribution = {f"{h:02d}": 0 for h in range(24)}
        for r in reports:
            if r.created_at is None:
                continue
            distribution[f"{hour_of(r.created_at):02d}"] += 1
        return distribution

    @staticmethod
    def compute_peak_hours(distribution: dict[str, int]) -> list[int]:
        if not distribution:
            return []
        sorted_hours = sorted(distribution.items(), key=lambda kv: kv[1], reverse=True)
        return [int(hour) for hour, count in sorted_hours[:3] if count > 0]

    @staticmethod
    def compute_crowd_score(reports: list[Report]) -> float:
        """Score 0..1 based on how recently and densely the cell has been tagged."""
        if not reports:
            return 0.0
        # Use timezone-aware "now" so comparisons work with Postgres
        # DateTime(timezone=True) while utcnow() stays naive for legacy callers.
        now = datetime.now(timezone.utc)  # noqa: UP017
        window = now - timedelta(hours=12)
        recent = [
            r
            for r in reports
            if r.created_at and as_utc_aware(r.created_at) >= window
        ]
        base = min(len(recent) / 12, 1.0)
        return round(base, 3)

    @staticmethod
    def compute_popularity_score(reports: list[Report]) -> float:
        if not reports:
            return 0.0
        return round(min(len(reports) / 30.0, 1.0) * 100.0, 2)

    @staticmethod
    def compute_confidence_score(reports: list[Report]) -> float:
        """Combines report count and temporal spread."""
        if not reports:
            return 0.0
        count_score = min(len(reports) / 20.0, 1.0)
        timestamps = [
            as_utc_aware(r.created_at)
            for r in reports
            if r.created_at is not None
        ]
        spread_score = 0.0
        if timestamps:
            timestamps.sort()
            delta_hours = (timestamps[-1] - timestamps[0]).total_seconds() / 3600
            spread_score = min(delta_hours / 48.0, 1.0)
        return round((0.65 * count_score + 0.35 * spread_score) * 100.0, 2)

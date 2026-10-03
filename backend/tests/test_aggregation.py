from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.models.report import Report
from app.services.aggregation_service import AggregationService


def _report(**overrides) -> Report:
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    base = dict(
        h3_index="8a1",
        resolution=8,
        latitude_raw=10.3,
        longitude_raw=123.88,
        category="food",
        tags_json=["food", "cafe"],
        traveler_type_snapshot="local",
        source_type="user",
        visibility_status="visible",
        created_at=now,
        updated_at=now,
    )
    base.update(overrides)
    return Report(**base)


def test_category_counts_are_lowercased():
    reports = [_report(category="Food"), _report(category="FOOD"), _report(category="safety")]
    counts = AggregationService.build_category_counts(reports)
    assert counts == {"food": 2, "safety": 1}


def test_tag_counts_aggregate_across_reports():
    reports = [
        _report(tags_json=["food", "cafe"]),
        _report(tags_json=["cafe", "dessert"]),
        _report(tags_json=["food"]),
    ]
    counts = AggregationService.build_tag_counts(reports)
    assert counts["food"] == 2
    assert counts["cafe"] == 2
    assert counts["dessert"] == 1


def test_time_distribution_has_24_hour_buckets():
    now = datetime(2026, 1, 1, 10)
    reports = [_report(created_at=now)]
    dist = AggregationService.compute_time_distribution(reports)
    assert len(dist) == 24
    assert dist["10"] == 1
    assert dist["09"] == 0


def test_crowd_score_prefers_recent_reports():
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    recent = [_report(created_at=now - timedelta(minutes=10)) for _ in range(6)]
    old = [_report(created_at=now - timedelta(days=3)) for _ in range(6)]
    assert AggregationService.compute_crowd_score(recent) > AggregationService.compute_crowd_score(old)


def test_confidence_score_zero_for_no_reports():
    assert AggregationService.compute_confidence_score([]) == 0.0

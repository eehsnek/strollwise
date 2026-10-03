from __future__ import annotations

from uuid import uuid4

from app.models.enums import BehaviorType, FunctionType
from app.models.merged_zone import MergedZone
from app.services.ranking_service import RankingService


def _zone(**overrides) -> MergedZone:
    base = dict(
        zone_id=uuid4(),
        display_name="Test Zone",
        slug=f"test-{uuid4().hex[:6]}",
        behavior_type=BehaviorType.MIXED_AREA.value,
        function_type=FunctionType.UNKNOWN.value,
        summary="test",
        live_status="active_now",
        polygon_geojson={"type": "Polygon", "coordinates": []},
        centroid_lat=10.3,
        centroid_lng=123.88,
        source_h3_indexes_json=[],
        crowd_level=0.3,
        local_presence_percent=60.0,
        peak_time_label=None,
        top_activities_json=[],
        confidence_score=50.0,
        priority_score=40.0,
        report_count=5,
    )
    base.update(overrides)
    return MergedZone(**base)


def test_food_filter_prioritizes_food_hotspots():
    food = _zone(function_type=FunctionType.FOOD_HOTSPOT.value, priority_score=20.0)
    other = _zone(function_type=FunctionType.RESIDENTIAL_ZONE.value, priority_score=55.0)
    ranked = RankingService.rank([other, food], filter_key="food")
    # Food filter adds +40 to food hotspots; 20+40=60 edges out residential 55.
    assert ranked[0].zone_id == food.zone_id


def test_safe_areas_filter_downranks_safety_concerns():
    unsafe = _zone(function_type=FunctionType.SAFETY_CONCERN.value, priority_score=80.0)
    safe = _zone(function_type=FunctionType.COMMERCIAL_ZONE.value, priority_score=40.0, confidence_score=90.0)
    ranked = RankingService.rank([unsafe, safe], filter_key="safe_areas")
    assert ranked[0].zone_id == safe.zone_id


def test_no_filter_sorts_by_priority():
    z1 = _zone(priority_score=10.0)
    z2 = _zone(priority_score=50.0)
    ranked = RankingService.rank([z1, z2], filter_key=None)
    assert ranked[0].zone_id == z2.zone_id


def test_rank_with_limit_returns_top_k_only():
    zones = [_zone(priority_score=float(i)) for i in range(20)]
    ranked = RankingService.rank(zones, filter_key=None, limit=5)
    assert len(ranked) == 5
    assert {z.priority_score for z in ranked} == {19.0, 18.0, 17.0, 16.0, 15.0}


def test_user_location_penalizes_far_zones():
    near = _zone(centroid_lat=10.3, centroid_lng=123.88, priority_score=40.0)
    far = _zone(centroid_lat=10.8, centroid_lng=124.5, priority_score=40.0)
    ranked = RankingService.rank([far, near], filter_key="popular_now", user_lat=10.3, user_lng=123.88)
    assert ranked[0].zone_id == near.zone_id


def test_recommend_alternatives_prefers_same_function_lower_crowd():
    current = _zone(
        function_type=FunctionType.FOOD_HOTSPOT.value,
        behavior_type=BehaviorType.LOCAL_AREA.value,
        crowd_level=0.9,
        priority_score=70.0,
        centroid_lat=10.3,
        centroid_lng=123.88,
    )
    better = _zone(
        function_type=FunctionType.FOOD_HOTSPOT.value,
        behavior_type=BehaviorType.LOCAL_AREA.value,
        crowd_level=0.45,
        priority_score=65.0,
        centroid_lat=10.305,
        centroid_lng=123.885,
    )
    mismatch = _zone(
        function_type=FunctionType.TRANSPORT_ZONE.value,
        behavior_type=BehaviorType.TOURIST_AREA.value,
        crowd_level=0.2,
        priority_score=95.0,
        centroid_lat=10.31,
        centroid_lng=123.89,
    )
    alternatives = RankingService.recommend_alternatives(current, [better, mismatch], limit=3)
    assert alternatives
    assert alternatives[0].zone_id == better.zone_id

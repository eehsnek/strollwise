from __future__ import annotations

from app.models.enums import BehaviorType
from app.models.h3_cell_aggregate import H3CellAggregate
from app.models.report import Report
from app.services import h3_service
from app.services.aggregation_service import AggregationService
from app.services.place_service import PlaceService
from app.services.zone_merge_service import ZoneMergeService


def _seed_food_reports(
    db_session,
    *,
    user_id,
    center_lat=10.3306,
    center_lng=123.9056,
    count=18,
):
    reports = []
    for i in range(count):
        lat = center_lat + (i % 6) * 0.0004
        lng = center_lng + (i // 6) * 0.0004
        h3_index = h3_service.latlng_to_cell(lat, lng, 8)
        r = Report(
            user_id=user_id,
            h3_index=h3_index,
            resolution=8,
            latitude_raw=lat,
            longitude_raw=lng,
            category="food",
            tags_json=["food", "cafe", "restaurant"],
            traveler_type_snapshot="local",
            source_type="user",
            visibility_status="visible",
        )
        db_session.add(r)
        reports.append(r)
    db_session.commit()
    return reports


def _create_user(db_session):
    from app.models.user import User

    user = User(
        email="merge-tester@example.com",
        password_hash="x",
        display_name="Tester",
        traveler_type="local",
    )
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    return user


def _rebuild_places_and_zones(db_session, affected_cells):
    places = PlaceService(db_session).rebuild_places_for_cells(affected_cells)
    zones = ZoneMergeService(db_session).recompute_for_places([p.place_id for p in places])
    return places, zones


def test_merge_creates_zone_for_place(db_session):
    user = _create_user(db_session)
    reports = _seed_food_reports(db_session, user_id=user.id)
    affected_cells = {r.h3_index for r in reports}

    AggregationService(db_session).recompute_cells(affected_cells)
    db_session.commit()

    places, zones = _rebuild_places_and_zones(db_session, affected_cells)

    assert places, "expected at least one place"
    assert zones, "expected at least one zone"
    zone = zones[0]
    assert zone.place_id is not None
    # IT Park catalog zone is international-dominant (Z007).
    assert zone.traveler_mix == "international"
    assert zone.function_type is None
    assert len(zone.source_h3_indexes_json or []) >= 1
    assert zone.polygon_geojson is not None
    assert zone.polygon_geojson.get("type") in ("Polygon", "MultiPolygon")


def test_merge_rollup_traveler_mix_for_mixed_reports(db_session):
    """Same place/cell with both local and international reporters → mixed zone."""
    user = _create_user(db_session)

    # Fuente Osmeña circle (mixed catalog zone Z010).
    lat, lng = 10.3099, 123.8915
    h3_index = h3_service.latlng_to_cell(lat, lng, 8)

    for _ in range(6):
        db_session.add(
            Report(
                user_id=user.id,
                h3_index=h3_index,
                resolution=8,
                latitude_raw=lat,
                longitude_raw=lng,
                category="food",
                tags_json=["food", "cafe"],
                traveler_type_snapshot="local",
                source_type="user",
                visibility_status="visible",
            )
        )
    for _ in range(10):
        db_session.add(
            Report(
                user_id=user.id,
                h3_index=h3_index,
                resolution=8,
                latitude_raw=lat,
                longitude_raw=lng,
                category="food",
                tags_json=["food", "cafe"],
                traveler_type_snapshot="international",
                source_type="user",
                visibility_status="visible",
            )
        )
    db_session.commit()

    AggregationService(db_session).recompute_cells([h3_index])
    db_session.commit()

    cell = db_session.get(H3CellAggregate, h3_index)
    assert cell.behavior_type == BehaviorType.MIXED_AREA.value

    _, zones = _rebuild_places_and_zones(db_session, [h3_index])
    assert zones
    assert zones[0].traveler_mix == "mixed"

from __future__ import annotations

from app.models.h3_cell_aggregate import H3CellAggregate
from app.models.report import Report
from app.services import h3_service
from app.services.aggregation_service import AggregationService
from app.services.place_service import PlaceService
from app.services.place_catalog import catalog_by_slug


def _create_user(db_session):
    from app.models.user import User

    user = User(
        email="place-tester@example.com",
        password_hash="x",
        display_name="Tester",
        traveler_type="local",
    )
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    return user


def test_uspf_tag_assigns_campus_place(db_session):
    user = _create_user(db_session)
    lat, lng = 10.3370, 123.9025
    h3_index = h3_service.latlng_to_cell(lat, lng, 8)
    db_session.add(
        Report(
            user_id=user.id,
            h3_index=h3_index,
            resolution=8,
            latitude_raw=lat,
            longitude_raw=lng,
            category="school",
            tags_json=["uspf campus", "school", "student"],
            traveler_type_snapshot="local",
            source_type="user",
            visibility_status="visible",
        )
    )
    db_session.commit()

    AggregationService(db_session).recompute_cells([h3_index])
    PlaceService(db_session).rebuild_places_for_cells([h3_index])

    cell = db_session.get(H3CellAggregate, h3_index)
    assert cell.place_id is not None
    catalog = catalog_by_slug("uspf_campus")
    assert catalog is not None

    place = PlaceService(db_session).place_repo.get_by_slug("uspf_campus")
    assert place is not None
    assert place.place_type == "school"
    assert h3_index in (place.source_h3_indexes_json or [])

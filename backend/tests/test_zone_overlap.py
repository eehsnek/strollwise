from __future__ import annotations

import uuid
from types import SimpleNamespace

from app.api.routers.zones import _find_current_zone


def _box(lng0, lat0, lng1, lat1, zid, name, **kwargs):
    poly = {
        "type": "Polygon",
        "coordinates": [
            [
                [lng0, lat0],
                [lng1, lat0],
                [lng1, lat1],
                [lng0, lat1],
                [lng0, lat0],
            ]
        ],
    }
    defaults = {
        "summary": None,
        "live_status": "quiet_now",
        "crowd_level": 0.2,
        "local_presence_percent": 50.0,
        "peak_time_label": None,
        "confidence_score": 40.0,
        "priority_score": 10.0,
        "source_h3_indexes_json": [],
        "top_activities_json": [],
    }
    defaults.update(kwargs)
    return SimpleNamespace(
        zone_id=zid,
        display_name=name,
        behavior_type="local_area",
        function_type="residential_zone",
        polygon_geojson=poly,
        centroid_lat=(lat0 + lat1) / 2,
        centroid_lng=(lng0 + lng1) / 2,
        **defaults,
    )


def test_find_current_zone_single_containment():
    a = _box(0, 0, 2, 2, uuid.uuid4(), "Big A")
    b = _box(0.5, 0.5, 1.5, 1.5, uuid.uuid4(), "Small B")
    # Point only in A
    z = _find_current_zone([a, b], lat=0.1, lng=0.1)
    assert z is not None
    assert z.display_name == "Big A"


def test_find_current_zone_overlap_returns_mixed():
    # Two unit squares sharing a 0.5x0.5 corner overlap: A [0,0]-[1,1], B [0.5,0.5]-[1.5,1.5]
    a = _box(0, 0, 1, 1, uuid.uuid4(), "Zone Alpha", crowd_level=0.3)
    b = _box(0.5, 0.5, 1.5, 1.5, uuid.uuid4(), "Zone Beta", crowd_level=0.5)
    z = _find_current_zone([a, b], lat=0.75, lng=0.75)
    assert z is not None
    assert "overlap" in z.display_name
    assert "Zone Alpha" in z.display_name and "Zone Beta" in z.display_name
    assert z.polygon_geojson["type"] in ("Polygon", "MultiPolygon")
    assert getattr(z, "_mixed_component_zone_ids", None) is not None
    assert len(z._mixed_component_zone_ids) == 2
    assert z.behavior_type == "mixed_area"
    assert z.function_type == "emerging_zone"
    assert z.crowd_level == 0.5


def test_zone_contains_point_respects_interior_hole():
    from app.api.routers import zones as zones_router

    geo = {
        "type": "Polygon",
        "coordinates": [
            [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0], [0.0, 0.0]],
            [[4.0, 4.0], [6.0, 4.0], [6.0, 6.0], [4.0, 6.0], [4.0, 4.0]],
        ],
    }
    assert zones_router._zone_contains_point(geo, lat=2.0, lng=2.0) is True
    assert zones_router._zone_contains_point(geo, lat=5.0, lng=5.0) is False

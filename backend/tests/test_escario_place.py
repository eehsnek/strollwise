from __future__ import annotations

from app.services.landmark_service import landmark_for_centroid
from app.services.place_catalog import catalog_place_at_point

# Typical Escario Street point (Capitol / Mango corridor), not IT Park.
ESCARIO_LAT = 10.3157
ESCARIO_LNG = 123.8919

FUENTE_LAT = 10.3100
FUENTE_LNG = 123.8916

IT_PARK_LAT = 10.3295
IT_PARK_LNG = 123.9067


def _catalog_slug_at(lat: float, lng: float) -> str | None:
    place = catalog_place_at_point(lat=lat, lng=lng)
    return place.slug if place else None


def test_escario_point_maps_to_escario_catalog_not_fuente():
    assert _catalog_slug_at(ESCARIO_LAT, ESCARIO_LNG) == "z014"
    assert _catalog_slug_at(ESCARIO_LAT, ESCARIO_LNG) != "z010"


def test_fuente_point_maps_to_fuente_catalog():
    assert _catalog_slug_at(FUENTE_LAT, FUENTE_LNG) == "z010"


def test_it_park_point_stays_it_park():
    assert _catalog_slug_at(IT_PARK_LAT, IT_PARK_LNG) == "z007"


def test_escario_nearest_landmark_is_nearby():
    _name, distance_km = landmark_for_centroid(ESCARIO_LAT, ESCARIO_LNG)
    assert distance_km < 1.5

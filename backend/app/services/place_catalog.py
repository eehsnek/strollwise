"""Curated Cebu place footprints — one place per catalog zone (14 total)."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from app.services.polygon_service import PolygonService
from app.services.zone_catalog import (
    CEBU_ZONE_CATALOG,
    ZoneCatalogEntry,
    cells_for_catalog_zone,
)
from app.utils.geo_utils import haversine_km
from app.utils.place_geometry import point_in_geojson


@dataclass(frozen=True)
class CatalogPlace:
    slug: str
    display_name: str
    default_place_type: str
    polygon_geojson: dict[str, Any]
    source_h3_indexes: tuple[str, ...] = ()
    tag_aliases: frozenset[str] = frozenset()


def _polygon(ring: list[list[float]]) -> dict[str, Any]:
    return {"type": "Polygon", "coordinates": [ring]}


def _place_type_for_zone(entry: ZoneCatalogEntry) -> str:
    zt = entry.zone_type.upper()
    if zt == "LOCAL":
        return "residential"
    if zt == "INTERNATIONAL":
        if "park" in entry.zone_name.lower() or "ocean" in entry.zone_name.lower():
            return "tourist"
        return "commercial"
    return "commercial"


def _slug_for_entry(entry: ZoneCatalogEntry) -> str:
    return entry.zone_id.lower()


def _aliases_for_entry(entry: ZoneCatalogEntry) -> frozenset[str]:
    base = {
        entry.zone_name.lower(),
        entry.zone_id.lower(),
        entry.city.lower(),
    }
    name = entry.zone_name.lower()
    if "it park" in name:
        base.update({"it park", "cebu it park", "it_park"})
    if "colon" in name:
        base.update({"colon", "colon street", "basilica", "magellan"})
    if "fuente" in name:
        base.update({"fuente", "fuente osmena", "fuente osmeña"})
    if "ayala" in name:
        base.update({"ayala", "ayala center"})
    if "carbon" in name:
        base.update({"carbon", "carbon market"})
    if "sm city" in name:
        base.update({"sm city", "sm city cebu"})
    if "srp" in name or "ocean" in name:
        base.update({"srp", "ocean park", "sm seaside", "il corso"})
    if "mactan" in name:
        base.update({"mactan", "lapu-lapu", "resort"})
    if entry.zone_name == "Escario":
        base.update({"escario", "escario street", "capitol site", "capitol"})
    if entry.zone_name == "Lahug":
        base.update({"lahug", "lahug residential", "salinas", "jy square"})
    if entry.zone_name == "Talamban":
        base.update({"talamban", "usc talamban"})
    return frozenset(base)


def _catalog_place(entry: ZoneCatalogEntry) -> CatalogPlace:
    cells = cells_for_catalog_zone(entry)
    polygon = PolygonService.cells_to_geojson_polygon(cells)
    return CatalogPlace(
        slug=_slug_for_entry(entry),
        display_name=entry.zone_name,
        default_place_type=_place_type_for_zone(entry),
        polygon_geojson=polygon,
        source_h3_indexes=tuple(cells),
        tag_aliases=_aliases_for_entry(entry),
    )


def place_catalog_for_db(db) -> tuple[CatalogPlace, ...]:
    """Build place footprints from DB-backed zone catalog (falls back to static)."""
    from app.services.zone_catalog import load_catalog_from_db

    entries = load_catalog_from_db(db)
    return tuple(
        _catalog_place(entry)
        for entry in sorted(entries, key=lambda entry: entry.radius_km)
    )


def catalog_place_at_point_db(db, *, lat: float, lng: float) -> CatalogPlace | None:
    """Among overlapping footprints, pick the zone whose center is closest."""
    from app.services.zone_catalog import load_catalog_from_db

    entries = load_catalog_from_db(db)
    zone_by_slug = {entry.zone_id.lower(): entry for entry in entries}
    places = place_catalog_for_db(db)
    containing: list[tuple[float, CatalogPlace]] = []
    for place in places:
        if not point_in_geojson(place.polygon_geojson, lat=lat, lng=lng):
            continue
        zone = zone_by_slug.get(place.slug)
        if zone is None:
            continue
        km = haversine_km(lat, lng, zone.center_lat, zone.center_lng)
        containing.append((km, place))
    if not containing:
        return None
    containing.sort(key=lambda pair: pair[0])
    return containing[0][1]


# Smaller footprints first so point-in-polygon picks the most specific zone.
CEBU_PLACE_CATALOG: tuple[CatalogPlace, ...] = tuple(
    _catalog_place(entry)
    for entry in sorted(CEBU_ZONE_CATALOG, key=lambda e: e.radius_km)
)


def catalog_by_slug(slug: str) -> CatalogPlace | None:
    for entry in CEBU_PLACE_CATALOG:
        if entry.slug == slug:
            return entry
    return None


_ZONE_BY_SLUG: dict[str, ZoneCatalogEntry] = {
    entry.zone_id.lower(): entry for entry in CEBU_ZONE_CATALOG
}


def catalog_place_at_point(*, lat: float, lng: float) -> CatalogPlace | None:
    """Among overlapping footprints, pick the zone whose center is closest."""
    containing: list[tuple[float, CatalogPlace]] = []
    for place in CEBU_PLACE_CATALOG:
        if not point_in_geojson(place.polygon_geojson, lat=lat, lng=lng):
            continue
        zone = _ZONE_BY_SLUG.get(place.slug)
        if zone is None:
            continue
        km = haversine_km(lat, lng, zone.center_lat, zone.center_lng)
        containing.append((km, place))
    if not containing:
        return None
    containing.sort(key=lambda pair: pair[0])
    return containing[0][1]

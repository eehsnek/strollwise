"""H3 cell indexes → map-ready polygon rings for zones and places."""
from __future__ import annotations

from collections.abc import Iterable

from app.core.config import settings
from app.services import h3_service


def close_ring(ring: list[list[float]]) -> list[list[float]]:
    if not ring:
        return []
    if ring[0] == ring[-1]:
        return ring
    return [*ring, ring[0]]


def rings_from_polygon_geojson(geojson: dict | None) -> list[list[list[float]]]:
    """Use the zone/place footprint as a single map ring (fallback only)."""
    if not geojson:
        return []
    geom_type = geojson.get("type")
    if geom_type == "Polygon":
        coords = geojson.get("coordinates") or []
        if coords and coords[0]:
            return [close_ring(list(coords[0]))]
    if geom_type == "MultiPolygon":
        rings: list[list[list[float]]] = []
        for part in geojson.get("coordinates") or []:
            if part and part[0]:
                rings.append(close_ring(list(part[0])))
        return rings
    return []


def display_h3_rings(source_indexes: Iterable[str] | None) -> list[list[list[float]]]:
    """One hex ring per H3 cell at native resolution (no finer uncompact)."""
    source = [idx for idx in (source_indexes or []) if idx]
    if not source:
        return []

    unique = list(dict.fromkeys(source))
    if len(unique) > 72:
        unique = unique[:72]

    return [close_ring(h3_service.cell_to_lnglat_ring(idx)) for idx in unique]


def zone_display_rings(
    polygon_geojson: dict | None,
    source_indexes: Iterable[str] | None,
) -> list[list[list[float]]]:
    """Prefer per-cell H3 hexes; polygon only when indexes are missing."""
    rings = display_h3_rings(source_indexes)
    if rings:
        return rings
    return rings_from_polygon_geojson(polygon_geojson)

"""Thin, version-tolerant wrapper around the H3 Python library.

The h3 package has renamed many functions between v3 and v4. We wrap them
here so the rest of the codebase stays stable, and so tests can swap in a
fake implementation if needed.
"""
from __future__ import annotations

from collections.abc import Iterable

import h3

from app.core.config import settings


def _compat(new_name: str, *old_names: str):
    fn = getattr(h3, new_name, None)
    if fn is not None:
        return fn
    for name in old_names:
        fn = getattr(h3, name, None)
        if fn is not None:
            return fn
    raise AttributeError(
        f"H3 library missing function {new_name} (aliases: {', '.join(old_names)})"
    )


_latlng_to_cell = _compat("latlng_to_cell", "geo_to_h3")
_cell_to_boundary = _compat("cell_to_boundary", "h3_to_geo_boundary")
_grid_disk = _compat("grid_disk", "k_ring")
_are_neighbors = _compat("are_neighbor_cells", "h3_indexes_are_neighbors")
_compact = _compat("compact_cells", "compact")
_uncompact = _compat("uncompact_cells", "uncompact")
_cell_to_latlng = _compat("cell_to_latlng", "h3_to_geo")
_get_resolution = _compat("get_resolution", "h3_get_resolution")
_cells_to_multi_polygon = getattr(h3, "cells_to_multi_polygon", None) or getattr(
    h3, "h3_set_to_multi_polygon", None
)

# h3-py 4.1+ removed `cells_to_multi_polygon` in favour of the H3Shape API.
# Build a compatibility shim that turns a cell list into the same nested
# coordinate structure the rest of the code expects (polygons → rings of
# (lat, lng) pairs).
if _cells_to_multi_polygon is None:
    _cells_to_h3shape = getattr(h3, "cells_to_h3shape", None)
    _h3shape_to_geo = getattr(h3, "h3shape_to_geo", None)
    if _cells_to_h3shape is None or _h3shape_to_geo is None:
        raise AttributeError(
            "H3 library missing polygon helpers "
            "(cells_to_multi_polygon or cells_to_h3shape+h3shape_to_geo)"
        )

    def _cells_to_multi_polygon(cells, geo_json=False):  # type: ignore[misc]
        """Emulate the pre-4.1 signature using the H3Shape API.

        Returns a list[polygon] where each polygon is list[ring] of
        (lat, lng) tuples — matching the old ``cells_to_multi_polygon``
        output shape the rest of the codebase consumes.
        """
        shape = _cells_to_h3shape(list(cells))
        geo = _h3shape_to_geo(shape)
        # geo is a GeoJSON-style dict; coordinates are [lng, lat].
        geom_type = geo.get("type")
        coords = geo.get("coordinates", [])
        if geom_type == "Polygon":
            polygons = [coords]
        elif geom_type == "MultiPolygon":
            polygons = coords
        else:
            polygons = []
        out = []
        for polygon in polygons:
            rings = []
            for ring in polygon:
                # Convert each [lng, lat] back to (lat, lng) tuple pairs
                # to match the pre-4.1 return shape.
                rings.append([(pt[1], pt[0]) for pt in ring])
            out.append(rings)
        return out


def latlng_to_cell(lat: float, lng: float, resolution: int | None = None) -> str:
    return _latlng_to_cell(lat, lng, resolution or settings.h3_resolution)


def cell_to_boundary(h3_index: str) -> list[tuple[float, float]]:
    """Return boundary as a list of (lat, lng) tuples (H3 v4 default ordering)."""
    return list(_cell_to_boundary(h3_index))


def cell_to_lnglat_ring(h3_index: str) -> list[list[float]]:
    """Return boundary as a GeoJSON-friendly list of [lng, lat] pairs."""
    return [[lng, lat] for (lat, lng) in cell_to_boundary(h3_index)]


def cell_centroid(h3_index: str) -> tuple[float, float]:
    lat, lng = _cell_to_latlng(h3_index)
    return float(lat), float(lng)


def grid_disk(h3_index: str, ring_size: int) -> list[str]:
    """All cells within ``ring_size`` k-rings of ``h3_index`` (inclusive)."""
    return list(_grid_disk(h3_index, ring_size))


def get_neighbors(h3_index: str, ring_size: int = 1) -> set[str]:
    disk = set(_grid_disk(h3_index, ring_size))
    disk.discard(h3_index)
    return disk


def are_neighbors(a: str, b: str) -> bool:
    try:
        return bool(_are_neighbors(a, b))
    except Exception:
        return b in get_neighbors(a, 1)


def compact_cells(cells: Iterable[str]) -> list[str]:
    return list(_compact(list(cells)))


def expand_cells(cells: Iterable[str], resolution: int | None = None) -> list[str]:
    res = resolution or settings.h3_resolution
    return list(_uncompact(list(cells), res))


def cell_resolution(h3_index: str) -> int:
    return int(_get_resolution(h3_index))


def cells_to_multipolygon(cells: Iterable[str]) -> list[list[list[list[float]]]]:
    """Return a MultiPolygon coordinate array using GeoJSON ordering ([lng, lat]).

    H3 v4's ``cells_to_multi_polygon`` returns polygons with rings in
    (lat, lng) order. We normalize to GeoJSON (lng, lat) and guarantee the
    outer ring is closed (first == last point).
    """
    cells_list = list(cells)
    if not cells_list:
        return []
    try:
        raw = _cells_to_multi_polygon(cells_list, True)
    except TypeError:
        raw = _cells_to_multi_polygon(cells_list)
    multi: list[list[list[list[float]]]] = []
    for polygon in raw:
        rings: list[list[list[float]]] = []
        for ring in polygon:
            points = [[float(pt[1]), float(pt[0])] for pt in ring]
            if points and points[0] != points[-1]:
                points.append(points[0])
            rings.append(points)
        multi.append(rings)
    return multi

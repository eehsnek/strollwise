"""Generates frontend-ready GeoJSON geometry from H3 cells."""
from __future__ import annotations

from collections.abc import Iterable
from typing import Any

from app.services import h3_service


class PolygonService:
    @staticmethod
    def cells_to_geojson_multipolygon(cells: Iterable[str]) -> dict[str, Any]:
        coords = h3_service.cells_to_multipolygon(cells)
        return {"type": "MultiPolygon", "coordinates": coords}

    @staticmethod
    def cells_to_geojson_polygon(cells: Iterable[str]) -> dict[str, Any]:
        """If the merged shape is a single polygon, return a GeoJSON Polygon; otherwise MultiPolygon."""
        coords = h3_service.cells_to_multipolygon(cells)
        if len(coords) == 1:
            return {"type": "Polygon", "coordinates": coords[0]}
        return {"type": "MultiPolygon", "coordinates": coords}

    @staticmethod
    def centroid_of_cells(cells: Iterable[str]) -> tuple[float, float]:
        cells_list = list(cells)
        if not cells_list:
            return (0.0, 0.0)
        lats = 0.0
        lngs = 0.0
        for cell in cells_list:
            lat, lng = h3_service.cell_centroid(cell)
            lats += lat
            lngs += lng
        count = len(cells_list)
        return (lats / count, lngs / count)

    @staticmethod
    def geojson_to_postgis_geometry(
        geojson: dict[str, Any],
        *,
        dialect_name: str | None = None,
    ) -> object | None:
        """Turn a GeoJSON Polygon/MultiPolygon into a GeoAlchemy2 WKTElement.

        Returns None on any failure, on SQLite (no PostGIS functions), or when
        the Geometry column is compiled to TEXT in tests.
        """
        if dialect_name == "sqlite":
            return None
        try:
            from geoalchemy2.elements import WKTElement  # type: ignore
            from shapely.geometry import shape  # type: ignore
            from shapely.geometry.multipolygon import MultiPolygon
        except ImportError:
            return None

        if not geojson:
            return None
        try:
            geom = shape(geojson)
        except Exception:
            return None

        if geom.geom_type == "Polygon":
            geom = MultiPolygon([geom])
        elif geom.geom_type != "MultiPolygon":
            return None

        return WKTElement(geom.wkt, srid=4326)

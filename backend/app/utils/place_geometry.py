"""Point-in-polygon helpers for place catalog membership."""
from __future__ import annotations


def point_in_ring(ring: list[list[float]], *, lat: float, lng: float) -> bool:
    """Ray-casting test; ring points are [lng, lat]."""
    inside = False
    if len(ring) < 3:
        return False
    j = len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i][0], ring[i][1]
        xj, yj = ring[j][0], ring[j][1]
        intersects = (yi > lat) != (yj > lat) and lng < (xj - xi) * (lat - yi) / (
            (yj - yi) or 1e-12
        ) + xi
        if intersects:
            inside = not inside
        j = i
    return inside


def point_in_geojson(geojson: dict, *, lat: float, lng: float) -> bool:
    if not geojson:
        return False
    geom_type = geojson.get("type")
    coords = geojson.get("coordinates", [])
    if geom_type == "Polygon":
        polygons = [coords]
    elif geom_type == "MultiPolygon":
        polygons = coords
    else:
        return False
    for polygon in polygons:
        if not polygon:
            continue
        outer = polygon[0]
        if not point_in_ring(outer, lat=lat, lng=lng):
            continue
        in_hole = False
        for hole in polygon[1:]:
            if hole and point_in_ring(hole, lat=lat, lng=lng):
                in_hole = True
                break
        if not in_hole:
            return True
    return False

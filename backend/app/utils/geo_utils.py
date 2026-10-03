from __future__ import annotations

import math


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle distance between two lat/lng points in kilometers."""
    r = 6371.0088
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    )
    return 2 * r * math.asin(math.sqrt(a))


def bbox_contains(
    lat: float,
    lng: float,
    min_lat: float,
    min_lng: float,
    max_lat: float,
    max_lng: float,
) -> bool:
    return min_lat <= lat <= max_lat and min_lng <= lng <= max_lng


def polygon_intersects_bbox(
    coords: list[list[list[float]]],
    min_lat: float,
    min_lng: float,
    max_lat: float,
    max_lng: float,
) -> bool:
    """Rough AABB overlap check against the first ring of a polygon."""
    if not coords or not coords[0]:
        return False
    ring = coords[0]
    lngs = [pt[0] for pt in ring]
    lats = [pt[1] for pt in ring]
    p_min_lng, p_max_lng = min(lngs), max(lngs)
    p_min_lat, p_max_lat = min(lats), max(lats)
    return not (
        p_max_lat < min_lat
        or p_min_lat > max_lat
        or p_max_lng < min_lng
        or p_min_lng > max_lng
    )

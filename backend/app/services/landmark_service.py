"""Maps a lat/lng to the nearest known Cebu landmark name.

The MVP name fallback from the spec is `<behavior> <function> near <landmark>`.
We keep this list in code for now; later it can be promoted to a DB table
populated from OSM / city administrative polygons.
"""
from __future__ import annotations

from dataclasses import dataclass

from app.utils.geo_utils import haversine_km


@dataclass(frozen=True)
class Landmark:
    name: str
    lat: float
    lng: float
    # Soft radius (km): when the centroid is within this distance we say
    # "near <landmark>"; outside it we fall back to "near <closest>".
    radius_km: float = 1.0


# Ordered by rough importance — the first landmark within `radius_km` wins
# if multiple overlap, so put more specific names first.
CEBU_LANDMARKS: tuple[Landmark, ...] = (
    Landmark("Escario Street", 10.3155, 123.8965, radius_km=0.45),
    Landmark("IT Park", 10.3306, 123.9056, radius_km=0.5),
    Landmark("Sugbo Mercado", 10.3289, 123.9071, radius_km=0.35),
    Landmark("Ayala Center", 10.3181, 123.9056, radius_km=0.5),
    Landmark("Larsian Fuente", 10.3096, 123.8944, radius_km=0.35),
    Landmark("Colon Street", 10.2970, 123.9020, radius_km=0.5),
    Landmark("Carbon Market", 10.2944, 123.9006, radius_km=0.45),
    Landmark("Basilica Minore del Santo Niño", 10.2941, 123.9016, radius_km=0.35),
    Landmark("USC Main", 10.3139, 123.8920, radius_km=0.5),
    Landmark("USC Talamban", 10.3545, 123.9139, radius_km=0.6),
    Landmark("Pier / Port", 10.2925, 123.9160, radius_km=0.6),
    Landmark("Lahug", 10.3388, 123.8893, radius_km=0.8),
    Landmark("Busay / Tops", 10.3700, 123.8780, radius_km=1.2),
    Landmark("Temple of Leah", 10.3714, 123.8795, radius_km=0.8),
    Landmark("Cebu Taoist Temple", 10.3410, 123.8885, radius_km=0.5),
    Landmark("Sirao Flower Garden", 10.3940, 123.8680, radius_km=0.9),
    Landmark("Mactan Resort Area", 10.2983, 124.0155, radius_km=1.5),
    Landmark("Magellan's Cross", 10.2938, 123.9013, radius_km=0.3),
    Landmark("Fort San Pedro", 10.2927, 123.9058, radius_km=0.4),
    Landmark("South Bus Terminal", 10.3001, 123.8931, radius_km=0.5),
    Landmark("Mango Avenue", 10.3123, 123.8976, radius_km=0.5),
    Landmark("SM Seaside", 10.2712, 123.8795, radius_km=0.6),
    Landmark("Fuente Osmeña", 10.3105, 123.8921, radius_km=0.5),
    Landmark("IL Corso / SRP", 10.2665, 123.8812, radius_km=0.8),
    Landmark("Capitol Site", 10.3197, 123.8949, radius_km=0.5),
    Landmark("Banilad", 10.3480, 123.9095, radius_km=0.7),
    Landmark("Mabolo", 10.3215, 123.9175, radius_km=0.6),
    Landmark("Mandaue Crossing", 10.3378, 123.9410, radius_km=0.8),
    Landmark("Talamban", 10.3770, 123.9145, radius_km=1.0),
    Landmark("Downtown Cebu", 10.2950, 123.9000, radius_km=0.4),
    Landmark("Cebu Business Park", 10.3160, 123.9050, radius_km=0.4),
)


def nearest_landmark(lat: float, lng: float) -> Landmark:
    """Return the closest landmark; always returns something."""
    best = min(
        CEBU_LANDMARKS,
        key=lambda l: haversine_km(lat, lng, l.lat, l.lng),
    )
    return best


def landmark_for_centroid(lat: float, lng: float) -> tuple[str, float]:
    """Return (landmark_name, distance_km) for the nearest landmark."""
    lm = nearest_landmark(lat, lng)
    return lm.name, haversine_km(lat, lng, lm.lat, lm.lng)

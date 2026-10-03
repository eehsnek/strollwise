"""Reference zone catalog for Cebu metro (behavioral defaults)."""
from __future__ import annotations

import math
from dataclasses import dataclass

from app.core.config import settings
from app.services import h3_service
from app.utils.geo_utils import haversine_km
from app.utils.traveler_gradient import local_ratio_from_traveler_mix


@dataclass(frozen=True)
class ZoneCatalogEntry:
    zone_id: str
    zone_name: str
    city: str
    zone_type: str  # LOCAL | INTERNATIONAL | MIXED
    radius_km: float
    center_lat: float
    center_lng: float
    characteristics: tuple[str, ...]
    default_local_ratio: float


def _k_ring_for_radius(radius_km: float) -> int:
    """Starting H3 k-ring (res 8) from thesis zone radius."""
    if radius_km <= 1.6:
        return 2
    if radius_km <= 2.0:
        return 3
    if radius_km <= 2.6:
        return 4
    if radius_km <= 3.2:
        return 5
    if radius_km <= 4.2:
        return 6
    return 7


def _max_cells_for_radius(radius_km: float) -> int:
    if radius_km <= 1.6:
        return 15
    if radius_km <= 2.0:
        return 25
    if radius_km <= 2.6:
        return 35
    if radius_km <= 3.2:
        return 45
    if radius_km <= 4.2:
        return 60
    return 72


def cells_for_catalog_zone(
    entry: ZoneCatalogEntry,
    *,
    resolution: int | None = None,
) -> list[str]:
    """H3 hex footprint: grid disk at res 8, clipped to ``radius_km``."""
    res = resolution or settings.h3_resolution
    seed = h3_service.latlng_to_cell(entry.center_lat, entry.center_lng, res)
    k = _k_ring_for_radius(entry.radius_km)
    candidates = h3_service.grid_disk(seed, k)
    within: list[tuple[float, str]] = []
    for cell in candidates:
        lat, lng = h3_service.cell_centroid(cell)
        km = haversine_km(lat, lng, entry.center_lat, entry.center_lng)
        if km <= entry.radius_km:
            within.append((km, cell))
    if not within:
        return [seed]
    within.sort(key=lambda pair: pair[0])
    cap = _max_cells_for_radius(entry.radius_km)
    return [cell for _, cell in within[:cap]]


def ring_from_center_km(
    lat: float,
    lng: float,
    radius_km: float,
    *,
    segments: int = 48,
) -> list[list[float]]:
    """Closed GeoJSON ring [lng, lat]: approximate circle with true km radius."""
    m_per_deg_lat = 111_320.0
    m_per_deg_lng = 111_320.0 * math.cos(math.radians(lat))
    radius_m = radius_km * 1000.0
    ring: list[list[float]] = []
    for i in range(segments):
        angle = 2.0 * math.pi * i / segments
        d_lat = (radius_m * math.cos(angle)) / m_per_deg_lat
        d_lng = (radius_m * math.sin(angle)) / m_per_deg_lng
        ring.append([lng + d_lng, lat + d_lat])
    ring.append(ring[0])
    return ring


CEBU_ZONE_CATALOG: tuple[ZoneCatalogEntry, ...] = (
    # --- Local-dominant (2–5 km per thesis spec) ---
    ZoneCatalogEntry(
        "Z001",
        "Talamban",
        "Cebu City",
        "LOCAL",
        2.5,
        10.3694,
        123.9185,
        (
            "residential_communities",
            "universities_schools",
            "daily_commuter_activity",
            "low_tourist_concentration",
        ),
        0.92,
    ),
    ZoneCatalogEntry(
        "Z002",
        "Pardo",
        "Cebu City",
        "LOCAL",
        3.0,
        10.2811,
        123.8456,
        (
            "residential_density",
            "public_transport",
            "community_markets",
            "limited_tourism",
        ),
        0.90,
    ),
    ZoneCatalogEntry(
        "Z003",
        "Minglanilla Proper",
        "Minglanilla",
        "LOCAL",
        4.0,
        10.2446,
        123.7963,
        (
            "suburban_residential",
            "local_commerce",
            "community_movement",
        ),
        0.90,
    ),
    ZoneCatalogEntry(
        "Z004",
        "Talisay Residential Area",
        "Talisay",
        "LOCAL",
        3.0,
        10.2449,
        123.8493,
        (
            "housing_communities",
            "schools_public_services",
            "routine_local_mobility",
        ),
        0.87,
    ),
    # --- International / tourist-dominant ---
    ZoneCatalogEntry(
        "Z005",
        "Mactan Resort Zone",
        "Lapu-Lapu City",
        "INTERNATIONAL",
        5.0,
        10.2998,
        124.0112,
        (
            "beach_resorts",
            "hotels_tourism",
            "airport_proximity",
            "foreign_visitors",
        ),
        0.08,
    ),
    ZoneCatalogEntry(
        "Z006",
        "Colon Basilica Heritage Zone",
        "Cebu City",
        "INTERNATIONAL",
        1.5,
        10.2942,
        123.9017,
        (
            "historical_landmarks",
            "tourist_attractions",
            "guided_tours",
            "heritage_activity",
        ),
        0.18,
    ),
    ZoneCatalogEntry(
        "Z007",
        "IT Park Business Zone",
        "Cebu City",
        "INTERNATIONAL",
        1.75,
        10.3295,
        123.9067,
        (
            "hotels",
            "foreign_business_visitors",
            "cafes_nightlife",
            "digital_nomads",
        ),
        0.22,
    ),
    ZoneCatalogEntry(
        "Z008",
        "SRP Tourism Belt",
        "Cebu City",
        "INTERNATIONAL",
        3.0,
        10.2869,
        123.8808,
        (
            "entertainment_destinations",
            "tourist_attractions",
            "large_visitor_movement",
        ),
        0.15,
    ),
    # --- Mixed ---
    ZoneCatalogEntry(
        "Z009",
        "Ayala Center Cebu",
        "Cebu City",
        "MIXED",
        2.5,
        10.3174,
        123.9058,
        (
            "shopping_malls",
            "offices",
            "hotels_restaurants",
            "tourist_local_overlap",
        ),
        0.55,
    ),
    ZoneCatalogEntry(
        "Z010",
        "Fuente Osmeña",
        "Cebu City",
        "MIXED",
        2.0,
        10.3100,
        123.8916,
        (
            "hospitals",
            "hotels",
            "restaurants",
            "public_transport",
        ),
        0.52,
    ),
    ZoneCatalogEntry(
        "Z011",
        "SM City Cebu",
        "Cebu City",
        "MIXED",
        2.5,
        10.3116,
        123.9182,
        (
            "commercial_center",
            "ferry_passengers",
            "shopping_dining",
            "visitor_overlap",
        ),
        0.48,
    ),
    ZoneCatalogEntry(
        "Z012",
        "Carbon Market Area",
        "Cebu City",
        "MIXED",
        2.0,
        10.2933,
        123.8998,
        (
            "local_market_culture",
            "tourist_curiosity",
            "commercial_activity",
            "heritage_exposure",
        ),
        0.58,
    ),
    ZoneCatalogEntry(
        "Z013",
        "Lahug",
        "Cebu City",
        "MIXED",
        3.5,
        10.3335,
        123.9030,
        (
            "it_park_influence",
            "residential_subdivisions",
            "universities_nearby",
            "cafes_coworking_nightlife",
        ),
        0.45,
    ),
    ZoneCatalogEntry(
        "Z014",
        "Escario",
        "Cebu City",
        "MIXED",
        2.5,
        10.3157,
        123.8919,
        (
            "hospitals",
            "residential_condos",
            "restaurants_cafes",
            "local_commuting",
        ),
        0.65,
    ),
)


def nearest_catalog_entry(lat: float, lng: float) -> ZoneCatalogEntry | None:
    """Closest catalog zone centroid to a point."""
    from app.utils.geo_utils import haversine_km

    best: ZoneCatalogEntry | None = None
    best_km = float("inf")
    for entry in CEBU_ZONE_CATALOG:
        km = haversine_km(lat, lng, entry.center_lat, entry.center_lng)
        if km < best_km:
            best_km = km
            best = entry
    return best


_BY_NAME: dict[str, ZoneCatalogEntry] = {
    e.zone_name.lower(): e for e in CEBU_ZONE_CATALOG
}

# Search / alias → catalog entry
_ALIASES: dict[str, str] = {
    "it park": "IT Park Business Zone",
    "cebu it park": "IT Park Business Zone",
    "it park hotel and business strip": "IT Park Business Zone",
    "colon": "Colon Basilica Heritage Zone",
    "colon street": "Colon Basilica Heritage Zone",
    "colon to basilica area": "Colon Basilica Heritage Zone",
    "basilica": "Colon Basilica Heritage Zone",
    "fuente": "Fuente Osmeña",
    "fuente osmena": "Fuente Osmeña",
    "fuente osmeña": "Fuente Osmeña",
    "fuente osmeña circle": "Fuente Osmeña",
    "ayala": "Ayala Center Cebu",
    "ayala center": "Ayala Center Cebu",
    "ayala center cebu area": "Ayala Center Cebu",
    "carbon": "Carbon Market Area",
    "carbon market": "Carbon Market Area",
    "carbon market redevelopment area": "Carbon Market Area",
    "sm city": "SM City Cebu",
    "sm city cebu area": "SM City Cebu",
    "srp": "SRP Tourism Belt",
    "ocean park": "SRP Tourism Belt",
    "cebu ocean park": "SRP Tourism Belt",
    "mactan": "Mactan Resort Zone",
    "mactan island resort area": "Mactan Resort Zone",
    "lapu-lapu": "Mactan Resort Zone",
    "escario street": "Escario",
    "lahug residential": "Lahug",
    "talisay residential districts": "Talisay Residential Area",
}


def catalog_entry_for_name(display_name: str) -> ZoneCatalogEntry | None:
    key = display_name.lower().strip()
    if key in _ALIASES:
        key = _ALIASES[key].lower()
    if key in _BY_NAME:
        return _BY_NAME[key]
    for entry in CEBU_ZONE_CATALOG:
        name = entry.zone_name.lower()
        if name in key or key in name:
            return entry
    return None


def default_local_ratio_for_name(
    display_name: str,
    traveler_mix: str,
    local_presence_percent: float = 0.0,
) -> float:
    entry = catalog_entry_for_name(display_name)
    if entry is not None:
        return entry.default_local_ratio
    return local_ratio_from_traveler_mix(
        traveler_mix,
        local_presence_percent=local_presence_percent or None,
    )


_catalog_db_cache: tuple[ZoneCatalogEntry, ...] | None = None


def invalidate_catalog_cache() -> None:
    global _catalog_db_cache
    _catalog_db_cache = None


def load_catalog_from_db(db) -> tuple[ZoneCatalogEntry, ...]:
    """Load active catalog entries from DB, falling back to static CEBU_ZONE_CATALOG."""
    global _catalog_db_cache
    if _catalog_db_cache is not None:
        return _catalog_db_cache
    from app.repositories.catalog_repository import CatalogRepository

    repo = CatalogRepository(db)
    if repo.count() == 0:
        repo.seed_from_static()
        db.flush()
    rows = repo.list_all(active_only=True)
    if rows:
        _catalog_db_cache = tuple(CatalogRepository.to_dataclass(r) for r in rows)
        return _catalog_db_cache
    _catalog_db_cache = CEBU_ZONE_CATALOG
    return _catalog_db_cache

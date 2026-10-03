"""Curated Cebu place picks for Trends → Places to go (no external API).

Picks are well-known, frequently reviewed places commonly cited for each
Cebu zone in travel guides and map listings (Google Maps / TripAdvisor style).
"""
from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from app.schemas.place_recommendation import PlaceRecommendation
from app.services.zone_catalog import CEBU_ZONE_CATALOG
from app.utils.geo_utils import haversine_km

_DATA_PATH = Path(__file__).resolve().parent.parent / "data" / "cebu_zone_place_picks.json"

# zone_id → area_key in JSON
_ZONE_AREA_KEYS: dict[str, str] = {
    "Z001": "talamban",
    "Z002": "pardo",
    "Z003": "minglanilla",
    "Z004": "talisay",
    "Z005": "mactan",
    "Z006": "colon",
    "Z007": "it_park",
    "Z008": "srp",
    "Z009": "ayala",
    "Z010": "fuente",
    "Z011": "sm_city",
    "Z012": "carbon",
    "Z013": "lahug",
    "Z014": "escario",
}

# Substrings in area labels → area_key
_LABEL_ALIASES: tuple[tuple[str, str], ...] = (
    ("it park", "it_park"),
    ("business zone", "it_park"),
    ("sugbo mercado", "it_park"),
    ("escario", "escario"),
    ("capitol site", "escario"),
    ("fuente", "fuente"),
    ("larsian", "fuente"),
    ("osmeña", "fuente"),
    ("osmena", "fuente"),
    ("ayala", "ayala"),
    ("business park", "ayala"),
    ("colon", "colon"),
    ("basilica", "colon"),
    ("heritage", "colon"),
    ("magellan", "colon"),
    ("carbon market", "carbon"),
    ("carbon", "carbon"),
    ("lahug", "lahug"),
    ("taoist", "lahug"),
    ("busay", "lahug"),
    ("sirao", "lahug"),
    ("temple of leah", "lahug"),
    ("sm city", "sm_city"),
    ("north reclamation", "sm_city"),
    ("srp", "srp"),
    ("seaside", "srp"),
    ("south road", "srp"),
    ("mactan", "mactan"),
    ("lapu-lapu", "mactan"),
    ("lapu lapu", "mactan"),
    ("resort zone", "mactan"),
    ("talamban", "talamban"),
    ("usc", "talamban"),
    ("pardo", "pardo"),
    ("minglanilla", "minglanilla"),
    ("talisay", "talisay"),
)


@lru_cache
def _load_curated() -> dict[str, dict[str, list[dict[str, Any]]]]:
    with _DATA_PATH.open(encoding="utf-8") as handle:
        raw = json.load(handle)
    if not isinstance(raw, dict):
        return {}
    return raw


def _resolve_area_key(area_label: str, lat: float, lng: float) -> str:
    area = area_label.lower()
    for needle, key in _LABEL_ALIASES:
        if needle in area:
            return key

    best_key = "lahug"
    best_km = float("inf")
    for entry in CEBU_ZONE_CATALOG:
        key = _ZONE_AREA_KEYS.get(entry.zone_id, "lahug")
        km = haversine_km(lat, lng, entry.center_lat, entry.center_lng)
        if km < best_km:
            best_km = km
            best_key = key
    return best_key


def _to_recommendation(raw: dict[str, Any]) -> PlaceRecommendation:
    return PlaceRecommendation(
        place_id=str(raw["place_id"]),
        name=str(raw["name"]),
        address=str(raw["address"]),
        lat=float(raw["lat"]),
        lng=float(raw["lng"]),
        rating=float(raw["rating"]) if raw.get("rating") is not None else None,
        review_count=int(raw.get("review_count") or 0),
        source="curated",
        maps_uri=None,
    )


def fetch_place_recommendations(
    *,
    lat: float,
    lng: float,
    vibe: str,
    area_label: str,
    limit: int = 8,
) -> list[PlaceRecommendation]:
    """Return curated, highest-mentioned-style picks for the area and vibe."""
    curated = _load_curated()
    area_key = _resolve_area_key(area_label, lat, lng)
    vibe_key = vibe.strip().lower() if vibe.strip() else "food"

    area_data = curated.get(area_key) or curated.get("lahug") or {}
    pool = (
        area_data.get(vibe_key)
        or area_data.get("food")
        or curated.get("lahug", {}).get("food")
        or []
    )

    sorted_pool = sorted(
        pool,
        key=lambda p: (
            -(float(p.get("rating") or 0)),
            -int(p.get("review_count") or 0),
        ),
    )
    cap = max(3, min(limit, 8))
    results = [_to_recommendation(raw) for raw in sorted_pool[:cap]]
    if results:
        return results

    return [
        PlaceRecommendation(
            place_id="curated-nearby",
            name=f"Explore near {area_label}",
            address=f"{area_label}, Cebu, Philippines",
            lat=lat,
            lng=lng,
            rating=4.0,
            review_count=0,
            source="curated",
        )
    ]

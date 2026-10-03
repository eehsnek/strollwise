"""Mapbox Geocoding API v5 — forward search for Cebu metro validation."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import httpx

from app.core.config import settings


@dataclass(frozen=True)
class MapboxGeocodeHit:
    name: str
    place_name: str
    lat: float
    lng: float
    relevance: float


class MapboxGeocodingService:
    """Thin client for Mapbox forward geocoding (Cebu-biased)."""

    def __init__(self, access_token: str | None = None) -> None:
        self._token = (access_token or settings.mapbox_access_token or "").strip()

    @property
    def enabled(self) -> bool:
        return bool(self._token) and "your_" not in self._token

    def forward(
        self,
        query: str,
        *,
        limit: int = 5,
        proximity_lng: float | None = None,
        proximity_lat: float | None = None,
    ) -> list[MapboxGeocodeHit]:
        if not self.enabled:
            return []
        q = query.strip()
        if len(q) < 2:
            return []

        from urllib.parse import quote

        lng = proximity_lng if proximity_lng is not None else settings.city_center_lng
        lat = proximity_lat if proximity_lat is not None else settings.city_center_lat
        # Cebu metro bbox: west,south,east,north
        bbox = "123.70,10.15,124.15,10.50"

        path = quote(q, safe="")
        url = (
            f"https://api.mapbox.com/geocoding/v5/mapbox.places/{path}.json"
            f"?access_token={self._token}"
            f"&limit={max(1, min(limit, 10))}"
            f"&proximity={lng},{lat}"
            f"&bbox={bbox}"
            f"&country=ph"
            f"&types=poi,place,locality,neighborhood,address"
        )

        try:
            with httpx.Client(timeout=10.0) as client:
                response = client.get(url)
                response.raise_for_status()
                data = response.json()
        except (httpx.HTTPError, ValueError):
            return []

        features = data.get("features") or []
        hits: list[MapboxGeocodeHit] = []
        for raw in features:
            if not isinstance(raw, dict):
                continue
            hit = _parse_feature(raw)
            if hit is not None:
                hits.append(hit)
        return hits


def _parse_feature(raw: dict[str, Any]) -> MapboxGeocodeHit | None:
    center = raw.get("center")
    if not isinstance(center, list) or len(center) < 2:
        return None
    try:
        lng = float(center[0])
        lat = float(center[1])
    except (TypeError, ValueError):
        return None
    text = (raw.get("text") or "").strip()
    place_name = (raw.get("place_name") or text).strip()
    relevance = float(raw.get("relevance") or 0.0)
    return MapboxGeocodeHit(
        name=text or place_name,
        place_name=place_name,
        lat=lat,
        lng=lng,
        relevance=relevance,
    )

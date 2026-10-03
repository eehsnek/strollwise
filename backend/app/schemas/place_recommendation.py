from __future__ import annotations

from pydantic import Field

from app.schemas.common import ORMModel


class PlaceRecommendation(ORMModel):
    """Curated place suggestion for Trends → Places to go."""

    place_id: str
    name: str
    address: str
    lat: float
    lng: float
    rating: float | None = None
    review_count: int = 0
    source: str = Field(default="curated")
    maps_uri: str | None = None

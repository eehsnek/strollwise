from __future__ import annotations

from pydantic import Field

from app.schemas.common import ORMModel


class CellListItem(ORMModel):
    h3_index: str
    ring: list[list[float]] = Field(default_factory=list)
    report_count: int = 0
    traveler_mix: str = "mixed"
    local_ratio: float = 0.5
    map_color: str = "#2FB7C8"
    function_type: str = "unknown"
    dominant_category: str | None = None
    confidence_score: float = 0.0
    crowd_score: float = 0.0
    place_id: str | None = None
    place_name: str | None = None
    centroid_lat: float = 0.0
    centroid_lng: float = 0.0

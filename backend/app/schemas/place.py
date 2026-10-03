from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import Field

from app.schemas.common import Centroid, ORMModel


class PlaceListItem(ORMModel):
    place_id: UUID
    display_name: str
    place_type: str
    polygon_geojson: dict[str, Any]
    centroid: Centroid
    report_count: int
    confidence_score: float
    cell_count: int = 0
    source_h3_rings: list[list[list[float]]] = Field(default_factory=list)
    updated_at: datetime | None = None


class PlaceDetail(PlaceListItem):
    source_h3_indexes: list[str] = Field(default_factory=list)
    top_tags: list[str] = Field(default_factory=list)


class PlaceSummary(ORMModel):
    place_id: UUID
    display_name: str
    place_type: str
    report_count: int = 0
    confidence_score: float = 0.0

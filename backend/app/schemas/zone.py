from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import Field

from app.schemas.common import Centroid, ORMModel
from app.schemas.place import PlaceSummary


class ZoneListItem(ORMModel):
    zone_id: UUID
    display_name: str
    behavior_type: str
    traveler_mix: str
    function_type: str | None = None
    place_id: UUID | None = None
    place_name: str | None = None
    place_type: str | None = None
    summary: str | None = None
    live_status: str
    polygon_geojson: dict[str, Any]
    centroid: Centroid
    crowd_level: float
    local_presence_percent: float
    local_ratio: float = 0.5
    map_color: str = "#2FB7C8"
    peak_time_label: str | None = None
    confidence_score: float
    priority_score: float
    source_h3_rings: list[list[list[float]]] = Field(default_factory=list)
    updated_at: datetime | None = None


class ZoneDetail(ORMModel):
    zone_id: UUID
    display_name: str
    behavior_type: str
    traveler_mix: str
    function_type: str | None = None
    place_id: UUID | None = None
    place_name: str | None = None
    place_type: str | None = None
    places: list[PlaceSummary] = Field(default_factory=list)
    summary: str | None = None
    live_status: str
    polygon_geojson: dict[str, Any]
    centroid: Centroid
    crowd_level: float
    local_presence_percent: float
    local_ratio: float = 0.5
    map_color: str = "#2FB7C8"
    peak_time_label: str | None = None
    top_activities: list[str] = Field(default_factory=list)
    confidence_score: float
    why_visit: str | None = None
    live_update: str | None = None
    nearby_zone_ids: list[UUID] = Field(default_factory=list)
    source_h3_indexes: list[str] = Field(default_factory=list)
    source_h3_rings: list[list[list[float]]] = Field(default_factory=list)
    report_count: int = 0
    updated_at: datetime | None = None


class ZoneLaunchContext(ORMModel):
    city_activity: str
    crowd_level_percent: float
    local_presence_percent: float
    peak_time_window: str | None = None


class CurrentZoneOverview(ORMModel):
    current_zone: ZoneListItem | None = None
    nearby_zones: list[ZoneListItem] = Field(default_factory=list)
    alternative_zones: list[ZoneListItem] = Field(default_factory=list)
    context: ZoneLaunchContext

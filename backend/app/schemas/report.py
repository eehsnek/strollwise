from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import Field

from app.schemas.common import ORMModel


class ReportCreate(ORMModel):
    latitude: float = Field(ge=-90.0, le=90.0)
    longitude: float = Field(ge=-180.0, le=180.0)
    category: str = Field(min_length=1, max_length=32)
    tags: list[str] = Field(default_factory=list)
    note_text: str | None = Field(default=None, max_length=1000)
    image_url: str | None = Field(default=None, max_length=500)
    image_mime_type: str | None = Field(default=None, max_length=80)
    image_size_bytes: int | None = Field(default=None, ge=0)
    source_type: str = Field(default="user", max_length=16)


class ReportPublic(ORMModel):
    id: UUID
    h3_index: str
    resolution: int
    category: str
    tags_json: list[str] = Field(default_factory=list)
    note_text: str | None = None
    image_url: str | None = None
    source_type: str
    visibility_status: str = "visible"
    created_at: datetime


class AggregationFeedback(ORMModel):
    h3_index: str
    pending_count: int
    matching_count: int
    threshold: int
    remaining_to_threshold: int
    threshold_met: bool
    public_zone_update: str


class ReportSubmissionResponse(ReportPublic):
    aggregation: AggregationFeedback


class PlaceTagMarker(ORMModel):
    """Map pin for a tagged report (e.g. USPF campus tags)."""

    id: UUID
    latitude: float
    longitude: float
    validated: bool

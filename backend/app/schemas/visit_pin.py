from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import Field

from app.schemas.common import ORMModel


class VisitPinCreate(ORMModel):
    latitude: float = Field(ge=-90.0, le=90.0)
    longitude: float = Field(ge=-180.0, le=180.0)
    label: str | None = Field(default=None, max_length=160)
    note: str | None = Field(default=None, max_length=280)


class VisitPinPublic(ORMModel):
    id: UUID
    h3_index: str
    latitude: float
    longitude: float
    label: str | None = None
    note: str | None = None
    source: str
    visit_count: int
    last_visited_at: datetime
    first_visited_at: datetime

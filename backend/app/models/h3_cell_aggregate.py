from __future__ import annotations

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base


class H3CellAggregate(Base):
    """One row per analyzed H3 cell.

    The primary key is the H3 index itself (text, base-16) because it is a
    natural, stable identifier and lets us upsert cheaply.
    """

    __tablename__ = "h3_cell_aggregates"

    h3_index: Mapped[str] = mapped_column(String(20), primary_key=True)
    resolution: Mapped[int] = mapped_column(Integer, nullable=False, default=8, index=True)

    report_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    local_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    international_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    mixed_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)

    category_counts_json: Mapped[dict] = mapped_column(
        JSONB, nullable=False, default=dict, server_default="{}"
    )
    tag_counts_json: Mapped[dict] = mapped_column(
        JSONB, nullable=False, default=dict, server_default="{}"
    )

    dominant_category: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    dominant_tags_json: Mapped[list[str]] = mapped_column(
        JSONB, nullable=False, default=list, server_default="[]"
    )

    behavior_type: Mapped[str] = mapped_column(
        String(32), nullable=False, default="mixed_area", index=True
    )
    function_type: Mapped[str] = mapped_column(
        String(32), nullable=False, default="unknown", index=True
    )
    place_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("places.place_id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    crowd_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    popularity_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    confidence_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)

    time_distribution_json: Mapped[dict] = mapped_column(
        JSONB, nullable=False, default=dict, server_default="{}"
    )
    peak_hours_json: Mapped[list[int]] = mapped_column(
        JSONB, nullable=False, default=list, server_default="[]"
    )

    last_report_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

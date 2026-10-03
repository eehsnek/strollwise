from __future__ import annotations

import uuid
from datetime import datetime
from typing import Optional

from geoalchemy2 import Geometry as _PostGISGeometry
from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.types import TypeDecorator

from app.core.database import Base


class _PostGISMultiPolygon(TypeDecorator):
    """PostGIS `Geometry` in production; plain `TEXT` on SQLite (no SpatiaLite)."""

    impl = Text
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == "postgresql":
            return dialect.type_descriptor(
                _PostGISGeometry(
                    geometry_type="MULTIPOLYGON",
                    srid=4326,
                    spatial_index=True,
                )
            )
        return dialect.type_descriptor(Text())


class MergedZone(Base):
    """Frontend-facing zone: one row per active place (traveler mix layer)."""

    __tablename__ = "merged_zones"

    zone_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    display_name: Mapped[str] = mapped_column(String(160), nullable=False)
    slug: Mapped[str] = mapped_column(String(180), nullable=False, unique=True, index=True)

    behavior_type: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    function_type: Mapped[Optional[str]] = mapped_column(String(32), nullable=True, index=True)
    traveler_mix: Mapped[Optional[str]] = mapped_column(String(16), nullable=True, index=True)
    place_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("places.place_id", ondelete="SET NULL"),
        nullable=True,
        unique=True,
        index=True,
    )

    summary: Mapped[Optional[str]] = mapped_column(String(600), nullable=True)
    live_status: Mapped[str] = mapped_column(String(24), nullable=False, default="quiet_now")

    polygon_geojson: Mapped[dict] = mapped_column(JSONB, nullable=False)
    # Optional PostGIS geometry for fast spatial queries. Stored as MultiPolygon.
    polygon_geometry: Mapped[Optional[object]] = mapped_column(
        _PostGISMultiPolygon(),
        nullable=True,
    )

    centroid_lat: Mapped[float] = mapped_column(Float, nullable=False)
    centroid_lng: Mapped[float] = mapped_column(Float, nullable=False)

    source_h3_indexes_json: Mapped[list[str]] = mapped_column(
        JSONB, nullable=False, default=list, server_default="[]"
    )

    crowd_level: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    local_presence_percent: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    peak_time_label: Mapped[Optional[str]] = mapped_column(String(40), nullable=True)
    top_activities_json: Mapped[list[str]] = mapped_column(
        JSONB, nullable=False, default=list, server_default="[]"
    )

    confidence_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    priority_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)

    report_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Report(Base):
    __tablename__ = "reports"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    h3_index: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    resolution: Mapped[int] = mapped_column(Integer, nullable=False, default=8)

    latitude_raw: Mapped[float] = mapped_column(Float, nullable=False)
    longitude_raw: Mapped[float] = mapped_column(Float, nullable=False)

    category: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    tags_json: Mapped[list[str]] = mapped_column(
        JSONB, nullable=False, default=list, server_default="[]"
    )
    note_text: Mapped[Optional[str]] = mapped_column(String(1000), nullable=True)
    image_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)

    source_type: Mapped[str] = mapped_column(String(16), nullable=False, default="user")
    traveler_type_snapshot: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    user_type_snapshot: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    country_of_origin_snapshot: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
    city_of_origin_snapshot: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
    visibility_status: Mapped[str] = mapped_column(
        String(16), nullable=False, default="visible"
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    user = relationship("User", back_populates="reports")
    media = relationship("Media", back_populates="report", cascade="all, delete-orphan")

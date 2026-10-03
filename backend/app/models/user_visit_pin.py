from __future__ import annotations

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import DateTime, Float, ForeignKey, Integer, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class UserVisitPin(Base):
    """Private map pin — only visible to the owning user."""

    __tablename__ = "user_visit_pins"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    h3_index: Mapped[str] = mapped_column(String(20), nullable=False, index=True)
    resolution: Mapped[int] = mapped_column(Integer, nullable=False, default=8)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    label: Mapped[Optional[str]] = mapped_column(String(160), nullable=True)
    note: Mapped[Optional[str]] = mapped_column(String(280), nullable=True)
    source: Mapped[str] = mapped_column(String(16), nullable=False, default="manual")
    visit_count: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    report_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("reports.id", ondelete="SET NULL"),
        nullable=True,
    )
    first_visited_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    last_visited_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), index=True
    )

    user = relationship("User", back_populates="visit_pins")

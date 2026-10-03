from __future__ import annotations

import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Boolean, DateTime, Float, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    email: Mapped[str] = mapped_column(String(320), unique=True, nullable=False, index=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    display_name: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
    manual_map_lat: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    manual_map_lng: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    traveler_type: Mapped[str] = mapped_column(String(32), nullable=False, default="mixed")
    country_of_origin: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
    city_of_origin: Mapped[Optional[str]] = mapped_column(String(120), nullable=True)
    user_type: Mapped[Optional[str]] = mapped_column(String(32), nullable=True)
    nationality: Mapped[Optional[str]] = mapped_column(String(8), nullable=True)
    age_range: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
    gender: Mapped[Optional[str]] = mapped_column(String(16), nullable=True)
    avatar_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    is_admin: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    accepted_research_consent: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    accepted_privacy_terms_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )

    reports = relationship("Report", back_populates="user", cascade="all, delete-orphan")
    visit_pins = relationship(
        "UserVisitPin", back_populates="user", cascade="all, delete-orphan"
    )
    saved_zones = relationship("SavedZone", back_populates="user", cascade="all, delete-orphan")

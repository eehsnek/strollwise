from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import EmailStr, Field, field_validator

from app.schemas.common import ORMModel
from app.schemas.report import ReportPublic
from app.utils.user_type_utils import ALLOWED_USER_TYPES


class UserPublic(ORMModel):
    id: UUID
    email: EmailStr
    display_name: str | None = None
    manual_map_lat: float | None = None
    manual_map_lng: float | None = None
    traveler_type: str
    country_of_origin: str | None = None
    city_of_origin: str | None = None
    user_type: str | None = None
    nationality: str | None = None
    age_range: str | None = None
    gender: str | None = None
    avatar_url: str | None = None
    is_admin: bool = False
    accepted_research_consent: bool = False
    accepted_privacy_terms_at: datetime | None = None
    created_at: datetime


class UserUpdate(ORMModel):
    display_name: str | None = Field(default=None, max_length=120)
    manual_map_lat: float | None = None
    manual_map_lng: float | None = None
    traveler_type: str | None = None
    country_of_origin: str | None = Field(default=None, max_length=120)
    city_of_origin: str | None = Field(default=None, max_length=120)
    user_type: str | None = Field(default=None, max_length=32)
    nationality: str | None = Field(default=None, max_length=8)
    age_range: str | None = Field(default=None, max_length=16)
    gender: str | None = Field(default=None, max_length=16)
    avatar_url: str | None = Field(default=None, max_length=500)

    @field_validator("country_of_origin", "city_of_origin", mode="before")
    @classmethod
    def strip_optional_text(cls, v: str | None) -> str | None:
        if v is None:
            return None
        s = str(v).strip()
        return s or None

    @field_validator("user_type", mode="before")
    @classmethod
    def validate_optional_user_type(cls, v: str | None) -> str | None:
        if v is None:
            return None
        key = str(v).strip().lower()
        if key not in ALLOWED_USER_TYPES:
            raise ValueError(
                "user_type must be one of: local_resident, international_visitor, "
                "domestic_traveler"
            )
        return key


class ProfileBadge(ORMModel):
    key: str
    label: str


class UserContributionStats(ORMModel):
    submitted: int
    approved: int
    pending: int


class UserContributionsResponse(ORMModel):
    stats: UserContributionStats
    recent_reports: list[ReportPublic]
    badges: list[ProfileBadge]
    contributor_label: str

"""Private visit pins — personal map history visible only to the owner."""
from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy.orm import Session

from app.models.user import User
from app.models.user_visit_pin import UserVisitPin
from app.repositories.visit_pin_repository import VisitPinRepository
from app.schemas.visit_pin import VisitPinCreate
from app.services import h3_service
from app.core.config import settings


class VisitPinService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.repo = VisitPinRepository(db)

    def record_visit(
        self,
        user: User,
        latitude: float,
        longitude: float,
        *,
        label: str | None = None,
        note: str | None = None,
        source: str = "manual",
        report_id: UUID | None = None,
    ) -> UserVisitPin:
        h3_index = h3_service.latlng_to_cell(
            latitude, longitude, settings.h3_resolution
        )
        now = datetime.now(timezone.utc)
        existing = self.repo.get_by_user_and_h3(user.id, h3_index)
        if existing is not None:
            existing.visit_count += 1
            existing.last_visited_at = now
            existing.latitude = latitude
            existing.longitude = longitude
            if label and label.strip():
                existing.label = label.strip()
            if note and note.strip():
                existing.note = note.strip()
            if report_id is not None:
                existing.report_id = report_id
            if source == "tag":
                existing.source = "tag"
            self.db.commit()
            self.db.refresh(existing)
            return existing

        pin = UserVisitPin(
            user_id=user.id,
            h3_index=h3_index,
            resolution=settings.h3_resolution,
            latitude=latitude,
            longitude=longitude,
            label=label.strip() if label else None,
            note=note.strip() if note else None,
            source=source,
            visit_count=1,
            report_id=report_id,
            first_visited_at=now,
            last_visited_at=now,
        )
        self.repo.upsert(pin)
        self.db.commit()
        self.db.refresh(pin)
        return pin

    def create_from_payload(self, user: User, payload: VisitPinCreate) -> UserVisitPin:
        return self.record_visit(
            user,
            payload.latitude,
            payload.longitude,
            label=payload.label,
            note=payload.note,
            source="manual",
        )

    def list_viewport(
        self,
        user_id: UUID,
        min_lat: float,
        max_lat: float,
        min_lng: float,
        max_lng: float,
        *,
        limit: int = 120,
    ) -> list[UserVisitPin]:
        return self.repo.list_in_viewport(
            user_id, min_lat, max_lat, min_lng, max_lng, limit=limit
        )

    def list_history(self, user_id: UUID, *, limit: int = 60) -> list[UserVisitPin]:
        return self.repo.list_history(user_id, limit=limit)

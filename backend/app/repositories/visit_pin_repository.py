from __future__ import annotations

from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.user_visit_pin import UserVisitPin


class VisitPinRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get_by_user_and_h3(self, user_id: UUID, h3_index: str) -> UserVisitPin | None:
        stmt = select(UserVisitPin).where(
            UserVisitPin.user_id == user_id,
            UserVisitPin.h3_index == h3_index,
        )
        return self.db.execute(stmt).scalar_one_or_none()

    def list_in_viewport(
        self,
        user_id: UUID,
        min_lat: float,
        max_lat: float,
        min_lng: float,
        max_lng: float,
        *,
        limit: int = 120,
    ) -> list[UserVisitPin]:
        stmt = (
            select(UserVisitPin)
            .where(
                UserVisitPin.user_id == user_id,
                UserVisitPin.latitude >= min_lat,
                UserVisitPin.latitude <= max_lat,
                UserVisitPin.longitude >= min_lng,
                UserVisitPin.longitude <= max_lng,
            )
            .order_by(UserVisitPin.last_visited_at.desc())
            .limit(limit)
        )
        return list(self.db.execute(stmt).scalars())

    def list_history(self, user_id: UUID, *, limit: int = 60) -> list[UserVisitPin]:
        stmt = (
            select(UserVisitPin)
            .where(UserVisitPin.user_id == user_id)
            .order_by(UserVisitPin.last_visited_at.desc())
            .limit(limit)
        )
        return list(self.db.execute(stmt).scalars())

    def upsert(self, pin: UserVisitPin) -> UserVisitPin:
        self.db.add(pin)
        self.db.flush()
        return pin

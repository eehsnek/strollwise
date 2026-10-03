from __future__ import annotations

from collections.abc import Iterable
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session, defer

from app.models.place import Place

_DEFER_POLYGON_GEOM = defer(Place.polygon_geometry)


class PlaceRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def get(self, place_id: UUID) -> Place | None:
        stmt = select(Place).where(Place.place_id == place_id).options(_DEFER_POLYGON_GEOM)
        return self.db.execute(stmt).scalar_one_or_none()

    def get_by_slug(self, slug: str) -> Place | None:
        stmt = select(Place).where(Place.slug == slug).options(_DEFER_POLYGON_GEOM)
        return self.db.execute(stmt).scalar_one_or_none()

    def list_active(self) -> list[Place]:
        stmt = (
            select(Place)
            .where(Place.is_active.is_(True), Place.report_count > 0)
            .options(_DEFER_POLYGON_GEOM)
        )
        return list(self.db.execute(stmt).scalars())

    def list_all_catalog(self) -> list[Place]:
        stmt = select(Place).where(Place.source == "catalog").options(_DEFER_POLYGON_GEOM)
        return list(self.db.execute(stmt).scalars())

    def list_by_ids(self, place_ids: Iterable[UUID]) -> list[Place]:
        ids = list(place_ids)
        if not ids:
            return []
        stmt = select(Place).where(Place.place_id.in_(ids)).options(_DEFER_POLYGON_GEOM)
        return list(self.db.execute(stmt).scalars())

    def upsert(self, place: Place) -> Place:
        existing = self.get_by_slug(place.slug)
        if existing is not None and existing.place_id != place.place_id:
            place.place_id = existing.place_id
        self.db.merge(place)
        self.db.flush()
        return place

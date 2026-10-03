from __future__ import annotations

from collections.abc import Iterable
from uuid import UUID

from sqlalchemy import desc, select
from sqlalchemy.orm import Session

from app.models.media import Media


class MediaRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def create(self, media: Media) -> Media:
        self.db.add(media)
        self.db.flush()
        return media

    def list_for_report(self, report_id: UUID) -> list[Media]:
        stmt = (
            select(Media)
            .where(Media.report_id == report_id)
            .order_by(desc(Media.created_at))
        )
        return list(self.db.execute(stmt).scalars())

    def list_for_reports(self, report_ids: Iterable[UUID]) -> list[Media]:
        ids = list(report_ids)
        if not ids:
            return []
        stmt = select(Media).where(Media.report_id.in_(ids))
        return list(self.db.execute(stmt).scalars())

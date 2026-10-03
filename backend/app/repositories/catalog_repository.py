from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.zone_catalog_entry import ZoneCatalogEntryModel
from app.services.zone_catalog import CEBU_ZONE_CATALOG, ZoneCatalogEntry


class CatalogRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def list_all(self, *, active_only: bool = False) -> list[ZoneCatalogEntryModel]:
        stmt = select(ZoneCatalogEntryModel).order_by(ZoneCatalogEntryModel.zone_id)
        if active_only:
            stmt = stmt.where(ZoneCatalogEntryModel.is_active.is_(True))
        return list(self.db.execute(stmt).scalars())

    def get(self, zone_id: str) -> ZoneCatalogEntryModel | None:
        return self.db.get(ZoneCatalogEntryModel, zone_id)

    def get_by_name(self, zone_name: str) -> ZoneCatalogEntryModel | None:
        stmt = select(ZoneCatalogEntryModel).where(
            ZoneCatalogEntryModel.zone_name == zone_name
        )
        return self.db.execute(stmt).scalar_one_or_none()

    def create(self, entry: ZoneCatalogEntryModel) -> ZoneCatalogEntryModel:
        self.db.add(entry)
        self.db.flush()
        return entry

    def save(self, entry: ZoneCatalogEntryModel) -> ZoneCatalogEntryModel:
        self.db.add(entry)
        self.db.flush()
        return entry

    def delete(self, entry: ZoneCatalogEntryModel) -> None:
        self.db.delete(entry)

    def count(self) -> int:
        return len(self.list_all())

    def seed_from_static(self) -> int:
        if self.count() > 0:
            return 0
        for entry in CEBU_ZONE_CATALOG:
            self.create(
                ZoneCatalogEntryModel(
                    zone_id=entry.zone_id,
                    zone_name=entry.zone_name,
                    city=entry.city,
                    zone_type=entry.zone_type,
                    radius_km=entry.radius_km,
                    center_lat=entry.center_lat,
                    center_lng=entry.center_lng,
                    characteristics_json=list(entry.characteristics),
                    default_local_ratio=entry.default_local_ratio,
                    is_active=True,
                )
            )
        self.db.flush()
        return len(CEBU_ZONE_CATALOG)

    @staticmethod
    def to_dataclass(row: ZoneCatalogEntryModel) -> ZoneCatalogEntry:
        return ZoneCatalogEntry(
            zone_id=row.zone_id,
            zone_name=row.zone_name,
            city=row.city,
            zone_type=row.zone_type,
            radius_km=row.radius_km,
            center_lat=row.center_lat,
            center_lng=row.center_lng,
            characteristics=tuple(row.characteristics_json or []),
            default_local_ratio=row.default_local_ratio,
        )

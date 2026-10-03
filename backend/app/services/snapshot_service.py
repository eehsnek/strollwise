"""Captures a daily `ZoneSnapshot` row per active merged zone.

Snapshots are the basis for zone history and trend analytics. The worker
runs once per day; this service is idempotent — if a snapshot for the
given (zone, date) already exists it's updated rather than duplicated.
"""
from __future__ import annotations

import logging
from datetime import date
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.merged_zone import MergedZone
from app.models.zone_snapshot import ZoneSnapshot
from app.repositories.zone_repository import ZoneRepository

log = logging.getLogger(__name__)


class SnapshotService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.repo = ZoneRepository(db)

    def snapshot_all_active(self, on_date: date | None = None) -> int:
        snapshot_date = on_date or date.today()
        zones = self.repo.list_active()
        written = 0
        for zone in zones:
            self._upsert_snapshot(zone, snapshot_date)
            written += 1
        self.db.commit()
        log.info("Wrote %d zone snapshots for %s", written, snapshot_date)
        return written

    def _upsert_snapshot(self, zone: MergedZone, snapshot_date: date) -> ZoneSnapshot:
        existing = self._find_existing(zone.zone_id, snapshot_date)
        summary = {
            "display_name": zone.display_name,
            "live_status": zone.live_status,
            "peak_time_label": zone.peak_time_label,
            "priority_score": float(zone.priority_score or 0.0),
            "top_activities": list(zone.top_activities_json or []),
        }
        if existing is not None:
            existing.behavior_type = zone.behavior_type
            existing.function_type = zone.function_type
            existing.crowd_level = float(zone.crowd_level or 0.0)
            existing.local_presence_percent = float(zone.local_presence_percent or 0.0)
            existing.confidence_score = float(zone.confidence_score or 0.0)
            existing.report_count = int(zone.report_count or 0)
            existing.summary_json = summary
            self.db.flush()
            return existing
        snapshot = ZoneSnapshot(
            zone_id=zone.zone_id,
            snapshot_date=snapshot_date,
            behavior_type=zone.behavior_type,
            function_type=zone.function_type,
            crowd_level=float(zone.crowd_level or 0.0),
            local_presence_percent=float(zone.local_presence_percent or 0.0),
            confidence_score=float(zone.confidence_score or 0.0),
            report_count=int(zone.report_count or 0),
            summary_json=summary,
        )
        return self.repo.add_snapshot(snapshot)

    def _find_existing(self, zone_id: UUID, snapshot_date: date) -> ZoneSnapshot | None:
        stmt = select(ZoneSnapshot).where(
            ZoneSnapshot.zone_id == zone_id,
            ZoneSnapshot.snapshot_date == snapshot_date,
        )
        return self.db.execute(stmt).scalar_one_or_none()

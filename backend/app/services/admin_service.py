"""Admin operations: zones, users, analytics, pipeline, dashboard."""
from __future__ import annotations

import csv
import io
import json
import logging
from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy.orm import Session

from app.core.cache import cache_delete_pattern
from app.models.merged_zone import MergedZone
from app.models.zone_catalog_entry import ZoneCatalogEntryModel
from app.repositories.audit_repository import AuditRepository
from app.repositories.catalog_repository import CatalogRepository
from app.repositories.report_repository import ReportRepository
from app.repositories.user_repository import UserRepository
from app.repositories.zone_repository import ZoneRepository
from app.schemas.admin import (
    AdminAnalyticsOverview,
    AdminAuditEntry,
    AdminAuditListResponse,
    AdminCatalogCreate,
    AdminCatalogEntry,
    AdminCatalogUpdate,
    AdminDashboardStats,
    AdminPipelineResult,
    AdminUserContributions,
    AdminUserListResponse,
    AdminUserSummary,
    AdminUserUpdate,
    AdminZoneSummary,
    AdminZoneUpdate,
    AdminZoneValidation,
)
from app.services.aggregation_service import AggregationService
from app.services.audit_service import AuditService
from app.services.city_pulse_service import CityPulseService
from app.services.place_service import PlaceService
from app.services.system_settings_service import SystemSettingsService
from app.services.admin_events import (
    publish_catalog_updated,
    publish_dashboard_refresh,
    publish_zones_updated,
)
from app.services.zone_catalog import invalidate_catalog_cache
from app.services.zone_merge_service import ZoneMergeService

log = logging.getLogger(__name__)


def _zone_lifecycle(zone: MergedZone) -> str:
    if zone.confidence_score >= 70 and zone.report_count >= 10:
        return "defined"
    if zone.report_count >= 3 or zone.confidence_score >= 40:
        return "emerging"
    return "unthreshold"


class AdminService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.zones = ZoneRepository(db)
        self.users = UserRepository(db)
        self.reports = ReportRepository(db)
        self.audit_repo = AuditRepository(db)
        self.catalog = CatalogRepository(db)
        self.audit = AuditService(db)

    # --- Dashboard -------------------------------------------------------

    def dashboard_stats(self) -> AdminDashboardStats:
        local = self.users.count_by_user_type("local_resident")
        intl = self.users.count_by_user_type("international_visitor")
        domestic = self.users.count_by_user_type("domestic_traveler")
        total_contrib = max(local + intl + domestic, 1)
        per_day = self.reports.count_reports_per_day(30)
        return AdminDashboardStats(
            pending_reports=self.reports.count_by_visibility("pending"),
            flagged_reports=self.reports.count_by_visibility("flagged"),
            active_zones=len(self.zones.list_active()),
            total_users=self.users.count_all(),
            local_contributor_ratio=round(local / total_contrib, 3),
            reports_last_30_days=[{"date": d, "count": c} for d, c in per_day],
        )

    # --- Zones -------------------------------------------------------------

    def list_zones(self) -> list[AdminZoneSummary]:
        rows = self.zones.list_active() + [
            z for z in self._all_zones() if not z.is_active
        ]
        seen: set[UUID] = set()
        out: list[AdminZoneSummary] = []
        for zone in rows:
            if zone.zone_id in seen:
                continue
            seen.add(zone.zone_id)
            out.append(self._zone_summary(zone))
        return out

    def zone_validation(self, zone_id: UUID) -> AdminZoneValidation | None:
        zone = self.zones.get(zone_id)
        if zone is None:
            return None
        h3_indexes = list(zone.source_h3_indexes_json or [])
        reports = self.reports.list_by_h3_indexes(h3_indexes) if h3_indexes else []
        categories: dict[str, int] = {}
        for r in reports:
            categories[r.category] = categories.get(r.category, 0) + 1
        top = max(categories, key=categories.get) if categories else None
        matching = categories.get(top, 0) if top else 0
        return AdminZoneValidation(
            zone_id=zone.zone_id,
            display_name=zone.display_name,
            total_signals=len(reports),
            matching_signals=matching,
            confidence=zone.confidence_score,
            top_category=top,
            last_updated=zone.updated_at,
            lifecycle_state=_zone_lifecycle(zone),
        )

    def update_zone(self, zone_id: UUID, payload: AdminZoneUpdate) -> AdminZoneSummary | None:
        zone = self.zones.get(zone_id)
        if zone is None:
            return None
        if payload.display_name is not None:
            zone.display_name = payload.display_name
        if payload.summary is not None:
            zone.summary = payload.summary
        if payload.live_status is not None:
            zone.live_status = payload.live_status
        if payload.is_active is not None:
            zone.is_active = payload.is_active
        self.zones.upsert(zone)
        self.db.commit()
        self.db.refresh(zone)
        return self._zone_summary(zone)

    def zone_history(self, zone_id: UUID) -> list[dict]:
        snaps = self.zones.list_snapshots(zone_id)
        return [
            {
                "snapshot_date": s.snapshot_date.isoformat(),
                "confidence_score": s.confidence_score,
                "report_count": s.report_count,
                "crowd_level": s.crowd_level,
            }
            for s in snaps
        ]

    # --- Users -------------------------------------------------------------

    def list_users(
        self, *, page: int = 1, page_size: int = 50, search: str | None = None
    ) -> AdminUserListResponse:
        rows, total = self.users.list_paginated(page=page, page_size=page_size, search=search)
        items = []
        for user in rows:
            counts = self.reports.count_grouped_by_visibility(user.id)
            items.append(
                AdminUserSummary(
                    id=user.id,
                    email=user.email,
                    display_name=user.display_name,
                    user_type=user.user_type,
                    traveler_type=user.traveler_type,
                    is_active=user.is_active,
                    is_admin=user.is_admin,
                    report_count=sum(counts.values()),
                    created_at=user.created_at,
                )
            )
        return AdminUserListResponse(items=items, total=total, page=page, page_size=page_size)

    def update_user(self, user_id: UUID, payload: AdminUserUpdate) -> AdminUserSummary | None:
        user = self.users.get_by_id(user_id)
        if user is None:
            return None
        if payload.is_active is not None:
            user.is_active = payload.is_active
        if payload.is_admin is not None:
            user.is_admin = payload.is_admin
        self.users.save(user)
        self.db.commit()
        self.db.refresh(user)
        counts = self.reports.count_grouped_by_visibility(user.id)
        return AdminUserSummary(
            id=user.id,
            email=user.email,
            display_name=user.display_name,
            user_type=user.user_type,
            traveler_type=user.traveler_type,
            is_active=user.is_active,
            is_admin=user.is_admin,
            report_count=sum(counts.values()),
            created_at=user.created_at,
        )

    def user_contributions(self, user_id: UUID) -> AdminUserContributions | None:
        user = self.users.get_by_id(user_id)
        if user is None:
            return None
        counts = self.reports.count_grouped_by_visibility(user.id)
        badges: list[str] = []
        if counts.get("visible", 0) >= 10:
            badges.append("contributor")
        if counts.get("visible", 0) >= 50:
            badges.append("power_contributor")
        return AdminUserContributions(
            user_id=user.id,
            total_reports=sum(counts.values()),
            visible_reports=counts.get("visible", 0),
            pending_reports=counts.get("pending", 0),
            flagged_reports=counts.get("flagged", 0),
            badges=badges,
        )

    # --- Analytics ---------------------------------------------------------

    def analytics_overview(self) -> AdminAnalyticsOverview:
        active = self.zones.list_active()
        emerging = sum(1 for z in active if _zone_lifecycle(z) == "emerging")
        defined = sum(1 for z in active if _zone_lifecycle(z) == "defined")
        pulse = CityPulseService(self.db).compute()
        return AdminAnalyticsOverview(
            pending_reports=self.reports.count_by_visibility("pending"),
            flagged_reports=self.reports.count_by_visibility("flagged"),
            visible_reports=self.reports.count_by_visibility("visible"),
            active_zones=len(active),
            local_contributors=self.users.count_by_user_type("local_resident"),
            international_contributors=self.users.count_by_user_type("international_visitor"),
            domestic_contributors=self.users.count_by_user_type("domestic_traveler"),
            zones_emerging=emerging,
            zones_defined=defined,
            city_pulse=pulse.model_dump(mode="json"),
        )

    def export_reports(self, fmt: str = "json") -> str:
        rows, _ = self.reports.list_admin(page=1, page_size=5000)
        grouped: dict[str, dict] = {}
        for r in rows:
            bucket = grouped.setdefault(
                r.h3_index,
                {
                    "h3_index": r.h3_index,
                    "categories": {},
                    "tag_counts": {},
                    "report_count": 0,
                },
            )
            bucket["report_count"] += 1
            bucket["categories"][r.category] = bucket["categories"].get(r.category, 0) + 1
            for tag in r.tags_json or []:
                bucket["tag_counts"][tag] = bucket["tag_counts"].get(tag, 0) + 1
        data = list(grouped.values())
        if fmt == "csv":
            buf = io.StringIO()
            writer = csv.DictWriter(
                buf,
                fieldnames=["h3_index", "report_count", "categories", "tag_counts"],
            )
            writer.writeheader()
            for row in data:
                writer.writerow(
                    {
                        "h3_index": row["h3_index"],
                        "report_count": row["report_count"],
                        "categories": json.dumps(row["categories"]),
                        "tag_counts": json.dumps(row["tag_counts"]),
                    }
                )
            return buf.getvalue()
        return json.dumps(data, indent=2)

    def export_zones(self, fmt: str = "json") -> str:
        zones = [self._zone_summary(z) for z in self._all_zones()]
        if fmt == "csv":
            buf = io.StringIO()
            writer = csv.DictWriter(
                buf,
                fieldnames=[
                    "zone_id",
                    "display_name",
                    "traveler_mix",
                    "confidence_score",
                    "report_count",
                    "lifecycle_state",
                ],
            )
            writer.writeheader()
            for z in zones:
                writer.writerow(
                    {
                        "zone_id": str(z.zone_id),
                        "display_name": z.display_name,
                        "traveler_mix": z.traveler_mix or "",
                        "confidence_score": z.confidence_score,
                        "report_count": z.report_count,
                        "lifecycle_state": z.lifecycle_state,
                    }
                )
            return buf.getvalue()
        return json.dumps([z.model_dump(mode="json") for z in zones], indent=2)

    def export_audit(self, fmt: str = "json") -> str:
        rows = self.audit_repo.list_all(limit=5000)
        entries = [
            AdminAuditEntry(
                id=r.id,
                actor_user_id=r.actor_user_id,
                action_type=r.action_type,
                entity_type=r.entity_type,
                entity_id=r.entity_id,
                payload_json=r.payload_json,
                created_at=r.created_at,
            )
            for r in rows
        ]
        if fmt == "csv":
            buf = io.StringIO()
            writer = csv.DictWriter(
                buf,
                fieldnames=[
                    "id",
                    "action_type",
                    "entity_type",
                    "entity_id",
                    "created_at",
                ],
            )
            writer.writeheader()
            for e in entries:
                writer.writerow(
                    {
                        "id": str(e.id),
                        "action_type": e.action_type,
                        "entity_type": e.entity_type,
                        "entity_id": e.entity_id or "",
                        "created_at": e.created_at.isoformat(),
                    }
                )
            return buf.getvalue()
        return json.dumps([e.model_dump(mode="json") for e in entries], indent=2)

    # --- Audit log viewer --------------------------------------------------

    def list_audit(
        self,
        *,
        page: int = 1,
        page_size: int = 50,
        action_type: str | None = None,
        entity_type: str | None = None,
    ) -> AdminAuditListResponse:
        rows, total = self.audit_repo.list_paginated(
            page=page,
            page_size=page_size,
            action_type=action_type,
            entity_type=entity_type,
        )
        items = [
            AdminAuditEntry(
                id=r.id,
                actor_user_id=r.actor_user_id,
                action_type=r.action_type,
                entity_type=r.entity_type,
                entity_id=r.entity_id,
                payload_json=r.payload_json,
                created_at=r.created_at,
            )
            for r in rows
        ]
        return AdminAuditListResponse(items=items, total=total, page=page, page_size=page_size)

    # --- Catalog -----------------------------------------------------------

    def list_catalog(self) -> list[AdminCatalogEntry]:
        self.catalog.seed_from_static()
        self.db.commit()
        return [self._catalog_entry(r) for r in self.catalog.list_all()]

    def create_catalog(self, payload: AdminCatalogCreate) -> AdminCatalogEntry:
        row = ZoneCatalogEntryModel(
            zone_id=payload.zone_id,
            zone_name=payload.zone_name,
            city=payload.city,
            zone_type=payload.zone_type.upper(),
            radius_km=payload.radius_km,
            center_lat=payload.center_lat,
            center_lng=payload.center_lng,
            characteristics_json=list(payload.characteristics),
            default_local_ratio=payload.default_local_ratio,
            is_active=payload.is_active,
        )
        self.catalog.create(row)
        self.db.commit()
        invalidate_catalog_cache()
        publish_catalog_updated(source="catalog_create")
        return self._catalog_entry(row)

    def update_catalog(
        self, zone_id: str, payload: AdminCatalogUpdate
    ) -> AdminCatalogEntry | None:
        row = self.catalog.get(zone_id)
        if row is None:
            return None
        if payload.zone_name is not None:
            row.zone_name = payload.zone_name
        if payload.city is not None:
            row.city = payload.city
        if payload.zone_type is not None:
            row.zone_type = payload.zone_type.upper()
        if payload.radius_km is not None:
            row.radius_km = payload.radius_km
        if payload.center_lat is not None:
            row.center_lat = payload.center_lat
        if payload.center_lng is not None:
            row.center_lng = payload.center_lng
        if payload.characteristics is not None:
            row.characteristics_json = list(payload.characteristics)
        if payload.default_local_ratio is not None:
            row.default_local_ratio = payload.default_local_ratio
        if payload.is_active is not None:
            row.is_active = payload.is_active
        self.catalog.save(row)
        self.db.commit()
        invalidate_catalog_cache()
        publish_catalog_updated(source="catalog_update")
        return self._catalog_entry(row)

    def delete_catalog(self, zone_id: str) -> bool:
        row = self.catalog.get(zone_id)
        if row is None:
            return False
        self.catalog.delete(row)
        self.db.commit()
        invalidate_catalog_cache()
        publish_catalog_updated(source="catalog_delete")
        return True

    # --- Pipeline ----------------------------------------------------------

    def rebuild_cells(self, h3_indexes: list[str] | None = None) -> AdminPipelineResult:
        started = datetime.now(timezone.utc)
        if h3_indexes:
            AggregationService(self.db).recompute_cells(h3_indexes)
            count = len(h3_indexes)
        else:
            rows, total = self.reports.list_admin(page=1, page_size=5000)
            indexes = {r.h3_index for r in rows}
            AggregationService(self.db).recompute_cells(indexes)
            count = len(indexes)
        self.db.commit()
        return AdminPipelineResult(
            job="rebuild-cells",
            started_at=started,
            affected_counts={"h3_cells": count},
            message=f"Recomputed {count} H3 cell aggregates.",
        )

    def rebuild_places(self) -> AdminPipelineResult:
        started = datetime.now(timezone.utc)
        places = PlaceService(self.db).rebuild_all()
        self.db.commit()
        return AdminPipelineResult(
            job="rebuild-places",
            started_at=started,
            affected_counts={"places": len(places)},
            message=f"Rebuilt {len(places)} places.",
        )

    def rebuild_zones(self) -> AdminPipelineResult:
        started = datetime.now(timezone.utc)
        zones = ZoneMergeService(self.db).rebuild_all()
        self.db.commit()
        publish_zones_updated(source="rebuild-zones")
        return AdminPipelineResult(
            job="rebuild-zones",
            started_at=started,
            affected_counts={"zones": len(zones)},
            message=f"Rebuilt {len(zones)} merged zones.",
        )

    def rebuild_all(self) -> AdminPipelineResult:
        started = datetime.now(timezone.utc)
        rows, _ = self.reports.list_admin(page=1, page_size=5000)
        indexes = {r.h3_index for r in rows}
        AggregationService(self.db).recompute_cells(indexes)
        self.db.commit()
        places = PlaceService(self.db).rebuild_all()
        zones = ZoneMergeService(self.db).rebuild_all()
        self.db.commit()
        publish_zones_updated(source="rebuild-all")
        publish_dashboard_refresh(source="rebuild-all")
        return AdminPipelineResult(
            job="rebuild-all",
            started_at=started,
            affected_counts={
                "h3_cells": len(indexes),
                "places": len(places),
                "zones": len(zones),
            },
            message="Full pipeline rebuild completed.",
        )

    def invalidate_cache(self) -> AdminPipelineResult:
        started = datetime.now(timezone.utc)
        cache_delete_pattern("zones:*")
        cache_delete_pattern("city:pulse:*")
        cache_delete_pattern("reports:pending:*")
        return AdminPipelineResult(
            job="invalidate-cache",
            started_at=started,
            affected_counts={},
            message="Cache invalidation requested.",
        )

    # --- Helpers -----------------------------------------------------------

    def _all_zones(self) -> list[MergedZone]:
        from sqlalchemy import select

        stmt = select(MergedZone)
        return list(self.db.execute(stmt).scalars())

    def _zone_summary(self, zone: MergedZone) -> AdminZoneSummary:
        return AdminZoneSummary(
            zone_id=zone.zone_id,
            display_name=zone.display_name,
            slug=zone.slug,
            traveler_mix=zone.traveler_mix,
            function_type=zone.function_type,
            live_status=zone.live_status,
            confidence_score=zone.confidence_score,
            report_count=zone.report_count,
            is_active=zone.is_active,
            lifecycle_state=_zone_lifecycle(zone),
        )

    @staticmethod
    def _catalog_entry(row: ZoneCatalogEntryModel) -> AdminCatalogEntry:
        return AdminCatalogEntry(
            zone_id=row.zone_id,
            zone_name=row.zone_name,
            city=row.city,
            zone_type=row.zone_type,
            radius_km=row.radius_km,
            center_lat=row.center_lat,
            center_lng=row.center_lng,
            characteristics=list(row.characteristics_json or []),
            default_local_ratio=row.default_local_ratio,
            is_active=row.is_active,
        )

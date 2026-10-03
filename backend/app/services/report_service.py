"""Handles the full lifecycle of a user report submission."""
from __future__ import annotations

import logging
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy.orm import Session

from app.core.cache import cache_delete_pattern, cache_set
from app.core.config import get_settings, settings
from app.models.enums import ReportCategory, VisibilityStatus
from app.models.media import Media
from app.models.report import Report
from app.models.user import User
from app.repositories.media_repository import MediaRepository
from app.repositories.report_repository import ReportRepository
from app.schemas.report import ReportCreate
from app.services import h3_service
from app.services.aggregation_service import AggregationService
from app.services.audit_service import AuditService
from app.services.place_service import PlaceService
from app.services.system_settings_service import effective_settings
from app.services.admin_events import publish_report_event, publish_zones_updated
from app.services.zone_merge_service import ZoneMergeService
from app.utils.user_type_utils import traveler_type_from_user_type

log = logging.getLogger(__name__)


def _distinct_contributors(reports: list[Report]) -> int:
    """Unique people who submitted a pending report in this H3 cell."""
    return len({r.user_id for r in reports})


class ReportValidationError(Exception):
    pass


@dataclass(frozen=True)
class AggregationFeedback:
    h3_index: str
    pending_count: int
    matching_count: int
    threshold: int
    remaining_to_threshold: int
    threshold_met: bool
    public_zone_update: str


@dataclass(frozen=True)
class ReportSubmissionResult:
    report: Report
    aggregation: AggregationFeedback


@dataclass(frozen=True)
class _RestrictedArea:
    name: str
    kind: str
    min_lat: float
    max_lat: float
    min_lng: float
    max_lng: float

    def contains(self, lat: float, lng: float) -> bool:
        return self.min_lat <= lat <= self.max_lat and self.min_lng <= lng <= self.max_lng


_RESTRICTED_AREAS = (
    _RestrictedArea(
        "Cebu City Medical Center",
        "hospital",
        10.2950,
        10.3010,
        123.8910,
        123.8985,
    ),
    _RestrictedArea(
        "Cebu City Hall and government center",
        "government",
        10.2915,
        10.2950,
        123.8995,
        123.9040,
    ),
    _RestrictedArea(
        "Camp Sergio Osmena police area",
        "police",
        10.3090,
        10.3145,
        123.8900,
        123.8960,
    ),
    _RestrictedArea(
        "private residential cluster",
        "private residential",
        10.3320,
        10.3385,
        123.8880,
        123.8965,
    ),
)


def _tags_refer_to_uspf(tags: list[str] | None) -> bool:
    """True when any tag mentions USPF (e.g. Flutter sends 'uspf campus' as one token)."""
    if not tags:
        return False
    return any("uspf" in str(t).lower() for t in tags)


class ReportService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.reports = ReportRepository(db)
        self.media = MediaRepository(db)
        self.audit = AuditService(db)
        self._cfg = effective_settings(db)

    def create_report(self, payload: ReportCreate, user: User) -> ReportSubmissionResult:
        self._validate(payload)
        self._validate_not_restricted(payload.latitude, payload.longitude)
        h3_index = h3_service.latlng_to_cell(
            payload.latitude, payload.longitude, settings.h3_resolution
        )
        self._validate_submission_limits(user, h3_index)
        report = Report(
            user_id=user.id,
            h3_index=h3_index,
            resolution=settings.h3_resolution,
            latitude_raw=payload.latitude,
            longitude_raw=payload.longitude,
            category=payload.category.lower(),
            tags_json=[t.lower() for t in payload.tags],
            note_text=payload.note_text,
            image_url=payload.image_url,
            source_type=payload.source_type,
            traveler_type_snapshot=(
                traveler_type_from_user_type(user.user_type)
                if user.user_type
                else (user.traveler_type or "mixed")
            ),
            user_type_snapshot=user.user_type,
            country_of_origin_snapshot=user.country_of_origin,
            city_of_origin_snapshot=user.city_of_origin,
            visibility_status=VisibilityStatus.PENDING.value,
        )
        self.reports.create(report)
        self.db.flush()

        # Persist media row if the client attached an uploaded image.
        if payload.image_url:
            self.media.create(
                Media(
                    report_id=report.id,
                    file_url=payload.image_url,
                    mime_type=payload.image_mime_type or "image/jpeg",
                    size_bytes=payload.image_size_bytes,
                )
            )

        # Audit trail.
        self.audit.record(
            actor_user_id=user.id,
            action_type="report.create",
            entity_type="report",
            entity_id=report.id,
            payload={
                "h3_index": h3_index,
                "category": report.category,
                "tags": report.tags_json,
                "has_image": bool(payload.image_url),
            },
        )

        user.updated_at = datetime.now(timezone.utc)  # noqa: UP017
        self.db.add(user)
        self.db.commit()
        self.db.refresh(report)
        try:
            label = self._visit_label_from_payload(payload)
            VisitPinService(self.db).record_visit(
                user,
                payload.latitude,
                payload.longitude,
                label=label,
                source="tag",
                report_id=report.id,
            )
        except Exception:
            log.exception("Failed to record private visit pin for report %s", report.id)
        self._write_pending_cache(h3_index)
        cache_delete_pattern("zones:feed*")
        publish_report_event("created", report_id=str(report.id), h3_index=h3_index)
        aggregation = self._build_aggregation_feedback(h3_index, report.category)
        threshold_met = self._approve_if_threshold_met(h3_index)
        if threshold_met:
            publish_report_event("approved", h3_index=h3_index, source="auto_threshold")
            publish_zones_updated(source="auto_threshold")
        if threshold_met:
            aggregation = AggregationFeedback(
                h3_index=aggregation.h3_index,
                pending_count=aggregation.pending_count,
                matching_count=aggregation.matching_count,
                threshold=aggregation.threshold,
                remaining_to_threshold=0,
                threshold_met=True,
                public_zone_update="Zone will update now that the threshold is met.",
            )
        return ReportSubmissionResult(report=report, aggregation=aggregation)

    # --- helpers ---------------------------------------------------------

    @staticmethod
    def _visit_label_from_payload(payload: ReportCreate) -> str | None:
        if payload.tags:
            return payload.tags[0].strip().title()
        return payload.category.replace("_", " ").title()

    @staticmethod
    def _validate(payload: ReportCreate) -> None:
        try:
            ReportCategory(payload.category.lower())
        except ValueError:
            raise ReportValidationError(
                f"Unsupported report category: {payload.category}"
            )
        if len(payload.tags) > 12:
            raise ReportValidationError("A report can include at most 12 tags")
        for tag in payload.tags:
            if len(tag) > 32:
                raise ReportValidationError("Tags must be 32 characters or fewer")

    @staticmethod
    def _validate_not_restricted(latitude: float, longitude: float) -> None:
        for area in _RESTRICTED_AREAS:
            if area.contains(latitude, longitude):
                raise ReportValidationError(
                    "This location is inside a sensitive "
                    f"{area.kind} area. Choose a nearby public area instead."
                )

    def _validate_submission_limits(self, user: User, h3_index: str) -> None:
        """Block duplicate pending tags, per-cell cooldown, and hourly floods."""
        cfg = self._cfg
        if self.reports.has_user_pending_in_h3(user.id, h3_index):
            raise ReportValidationError(
                "You already have a pending tag in this map cell. "
                "Wait for community validation or choose a nearby spot."
            )

        cooldown_hours = cfg.report_cooldown_hours_per_cell
        if cooldown_hours > 0:
            since = datetime.now(timezone.utc) - timedelta(hours=cooldown_hours)
            if (
                self.reports.latest_user_report_in_h3_since(
                    user.id, h3_index, since
                )
                is not None
            ):
                raise ReportValidationError(
                    "You tagged this map cell recently. "
                    f"Try again after {cooldown_hours} hours or pick a nearby area."
                )

        max_per_hour = cfg.report_max_per_user_per_hour
        if max_per_hour > 0:
            since = datetime.now(timezone.utc) - timedelta(hours=1)
            if self.reports.count_user_reports_since(user.id, since) >= max_per_hour:
                raise ReportValidationError(
                    "Too many tags in the last hour. Please wait before submitting again."
                )

    def recent_feed(self, limit: int = 50) -> list[Report]:
        return self.reports.list_recent(limit)

    def reports_in_zone(self, zone_h3_indexes: list[str]) -> list[Report]:
        return self.reports.list_by_h3_indexes(zone_h3_indexes)

    def report_by_id(self, report_id: UUID) -> Report | None:
        return self.reports.get_by_id(report_id)

    def list_place_markers(
        self,
        min_lat: float,
        max_lat: float,
        min_lng: float,
        max_lng: float,
        tag: str,
        *,
        limit: int = 120,
    ) -> list[Report]:
        return self.reports.list_in_viewport_with_tag(
            min_lat,
            max_lat,
            min_lng,
            max_lng,
            tag,
            limit=limit,
        )

    def list_own_pending_pins(
        self,
        user_id: UUID,
        min_lat: float,
        max_lat: float,
        min_lng: float,
        max_lng: float,
        *,
        limit: int = 80,
    ) -> list[Report]:
        return self.reports.list_own_pending_in_viewport(
            user_id,
            min_lat,
            max_lat,
            min_lng,
            max_lng,
            limit=limit,
        )

    def _write_pending_cache(self, h3_index: str) -> None:
        pending_reports = self.reports.list_pending_by_h3_index(h3_index)
        cache_set(
            f"reports:pending:{h3_index}",
            {
                "h3_index": h3_index,
                "pending_count": len(pending_reports),
                "latest_report_ids": [str(r.id) for r in pending_reports[:20]],
            },
            settings.pending_cache_ttl_seconds,
        )

    def _build_aggregation_feedback(
        self, h3_index: str, category: str
    ) -> AggregationFeedback:
        pending_reports = self.reports.list_pending_by_h3_index(h3_index)
        has_uspf = any(_tags_refer_to_uspf(r.tags_json) for r in pending_reports)
        min_reports = (
            1
            if has_uspf
            else max(self._cfg.pending_min_reports_per_cell, 1)
        )
        people_in_cell = _distinct_contributors(pending_reports)
        matching_count = people_in_cell
        remaining = max(min_reports - people_in_cell, 0)
        return AggregationFeedback(
            h3_index=h3_index,
            pending_count=len(pending_reports),
            matching_count=matching_count,
            threshold=min_reports,
            remaining_to_threshold=remaining,
            threshold_met=remaining == 0,
            public_zone_update=(
                "Zone will update after the threshold is reached."
                if remaining
                else "Zone will update after approval finishes."
            ),
        )

    def _approve_if_threshold_met(self, h3_index: str) -> bool:
        pending_reports = self.reports.list_pending_by_h3_index(h3_index)
        has_uspf = any(_tags_refer_to_uspf(r.tags_json) for r in pending_reports)
        # Campus "USPF" tags: one submission in the cell is enough to validate and
        # publish the zone (per-user cooldown / duplicate pending still apply on submit).
        min_reports = (
            1
            if has_uspf
            else max(self._cfg.pending_min_reports_per_cell, 1)
        )
        if _distinct_contributors(pending_reports) < min_reports:
            return False

        category_counts = Counter((r.category or "").lower() for r in pending_reports)
        top_count = max(category_counts.values(), default=0)
        agreement = (top_count / len(pending_reports)) if pending_reports else 0.0
        if agreement < self._cfg.pending_agreement_ratio:
            return False

        for report in pending_reports:
            report.visibility_status = VisibilityStatus.VISIBLE.value

        self.db.commit()

        affected = {h3_index}
        affected.update(h3_service.get_neighbors(h3_index, ring_size=1))
        try:
            AggregationService(self.db).recompute_cells(affected)
            self.db.commit()
            places = PlaceService(self.db).rebuild_places_for_cells(affected)
            place_ids = [p.place_id for p in places]
            ZoneMergeService(self.db).recompute_for_places(place_ids)

            cache_delete_pattern("zones:vp:*")
            cache_delete_pattern("zones:feed*")
            cache_delete_pattern("city:pulse:*")
            cache_delete_pattern(f"reports:pending:{h3_index}")
        except Exception:
            # Reports are already visible; do not fail the HTTP request if
            # derived data (aggregates / merged zones) fails to refresh.
            log.exception(
                "aggregation or zone merge failed after approving reports "
                "for h3_index=%s",
                h3_index,
            )
            self.db.rollback()
        return True

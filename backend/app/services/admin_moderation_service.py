"""Admin moderation: review pending/flagged reports with privacy-safe views."""
from __future__ import annotations

import logging
from collections import Counter
from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy.orm import Session

from app.core.cache import cache_delete_pattern
from app.core.config import settings
from app.models.enums import VisibilityStatus
from app.models.report import Report
from app.models.user import User
from app.repositories.report_repository import ReportRepository
from app.schemas.admin import (
    AdminCellContext,
    AdminReportDetail,
    AdminReportListResponse,
    AdminReportSummary,
    ModerationAction,
    ModerationActionResult,
    ModerationBulkRequest,
    ModerationBulkResult,
    ModerationQueueFilter,
)
from app.services import h3_service
from app.services.aggregation_service import AggregationService
from app.services.audit_service import AuditService
from app.services.place_service import PlaceService
from app.services.report_service import _distinct_contributors, _tags_refer_to_uspf
from app.services.system_settings_service import SystemSettingsService
from app.services.admin_events import publish_report_event, publish_zones_updated
from app.services.zone_merge_service import ZoneMergeService

log = logging.getLogger(__name__)


class AdminModerationService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.reports = ReportRepository(db)
        self.audit = AuditService(db)
        self.cfg = SystemSettingsService(db).get_effective_settings()

    def list_reports(
        self,
        *,
        queue: ModerationQueueFilter = ModerationQueueFilter.PENDING,
        page: int = 1,
        page_size: int = 50,
    ) -> AdminReportListResponse:
        if queue == ModerationQueueFilter.DUPLICATES:
            items = self._list_duplicates(page=page, page_size=page_size)
            return AdminReportListResponse(
                items=items,
                total=len(items),
                page=page,
                page_size=page_size,
            )
        if queue == ModerationQueueFilter.NEAR_THRESHOLD:
            items = self._list_near_threshold(page=page, page_size=page_size)
            return AdminReportListResponse(
                items=items,
                total=len(items),
                page=page,
                page_size=page_size,
            )

        status = None if queue == ModerationQueueFilter.ALL else queue.value
        rows, total = self.reports.list_admin(
            visibility_status=status,
            page=page,
            page_size=page_size,
        )
        return AdminReportListResponse(
            items=[self._to_summary(r) for r in rows],
            total=total,
            page=page,
            page_size=page_size,
        )

    def get_report(self, report_id: UUID) -> AdminReportDetail | None:
        report = self.reports.get_by_id(report_id)
        if report is None:
            return None
        summary = self._to_summary(report)
        ctx = self._cell_context(report.h3_index)
        return AdminReportDetail(**summary.model_dump(), cell_context=ctx)

    def apply_action(
        self,
        report_id: UUID,
        action: ModerationAction,
        admin: User,
    ) -> ModerationActionResult | None:
        report = self.reports.get_by_id(report_id)
        if report is None:
            return None

        pipeline_triggered = False
        if action == ModerationAction.APPROVE:
            report.visibility_status = VisibilityStatus.VISIBLE.value
            audit_action = "report.admin_approve"
        elif action == ModerationAction.REJECT:
            report.visibility_status = VisibilityStatus.REMOVED.value
            audit_action = "report.admin_reject"
        elif action == ModerationAction.FLAG:
            report.visibility_status = VisibilityStatus.FLAGGED.value
            audit_action = "report.admin_flag"
        else:
            report.visibility_status = VisibilityStatus.PENDING.value
            audit_action = "report.admin_keep_pending"

        self.db.commit()
        self.db.refresh(report)

        self.audit.record(
            actor_user_id=admin.id,
            action_type=audit_action,
            entity_type="report",
            entity_id=report.id,
            payload={
                "h3_index": report.h3_index,
                "category": report.category,
                "visibility_status": report.visibility_status,
            },
        )
        self.db.commit()

        if action == ModerationAction.APPROVE:
            pipeline_triggered = self._run_pipeline(report.h3_index)
            publish_report_event("approved", report_id=str(report.id), h3_index=report.h3_index)
            publish_zones_updated(source="admin_moderation")
        elif action in (ModerationAction.REJECT, ModerationAction.FLAG):
            event = "rejected" if action == ModerationAction.REJECT else "flagged"
            publish_report_event(event, report_id=str(report.id), h3_index=report.h3_index)

        return ModerationActionResult(
            report=self._to_summary(report),
            cell_context=self._cell_context(report.h3_index),
            pipeline_triggered=pipeline_triggered,
        )

    def bulk_action(
        self,
        payload: ModerationBulkRequest,
        admin: User,
    ) -> ModerationBulkResult:
        updated = 0
        failed: list[UUID] = []
        for report_id in payload.report_ids:
            result = self.apply_action(report_id, payload.action, admin)
            if result is None:
                failed.append(report_id)
            else:
                updated += 1
        return ModerationBulkResult(updated=updated, failed=failed)

    def _to_summary(self, report: Report) -> AdminReportSummary:
        ctx = self._cell_context(report.h3_index)
        since = datetime.now(timezone.utc) - timedelta(
            hours=max(self.cfg.report_cooldown_hours_per_cell, 24)
        )
        dupes = self.reports.list_by_h3_and_category_since(
            report.h3_index,
            report.category,
            since,
            exclude_id=report.id,
        )
        return AdminReportSummary(
            id=report.id,
            h3_index=report.h3_index,
            category=report.category,
            tags=list(report.tags_json or []),
            note_text=report.note_text,
            visibility_status=report.visibility_status,
            confidence_score=round(ctx.category_agreement * 100, 1),
            contributor_count=ctx.distinct_contributors,
            duplicate_count=len(dupes),
            created_at=report.created_at,
            image_url=report.image_url,
        )

    def _cell_context(self, h3_index: str) -> AdminCellContext:
        pending = self.reports.list_pending_by_h3_index(h3_index)
        visible_count = len(
            [r for r in self.reports.list_by_h3_indexes([h3_index])]
        )
        flagged_stmt_count = sum(
            1 for r in pending if r.visibility_status == VisibilityStatus.FLAGGED.value
        )
        has_uspf = any(_tags_refer_to_uspf(r.tags_json) for r in pending)
        threshold = (
            1
            if has_uspf
            else max(self.cfg.pending_min_reports_per_cell, 1)
        )
        contributors = _distinct_contributors(pending)
        category_counts = Counter((r.category or "").lower() for r in pending)
        top_category = category_counts.most_common(1)[0][0] if category_counts else None
        top_count = max(category_counts.values(), default=0)
        agreement = (top_count / len(pending)) if pending else 0.0
        return AdminCellContext(
            h3_index=h3_index,
            pending_count=len(pending),
            visible_count=visible_count,
            flagged_count=flagged_stmt_count,
            distinct_contributors=contributors,
            top_category=top_category,
            category_agreement=round(agreement, 3),
            threshold=threshold,
            threshold_met=contributors >= threshold
            and agreement >= self.cfg.pending_agreement_ratio,
        )

    def _list_duplicates(self, *, page: int, page_size: int) -> list[AdminReportSummary]:
        since = datetime.now(timezone.utc) - timedelta(hours=24)
        rows, _ = self.reports.list_admin(
            visibility_status=VisibilityStatus.PENDING.value,
            page=1,
            page_size=500,
        )
        out: list[AdminReportSummary] = []
        for report in rows:
            dupes = self.reports.list_by_h3_and_category_since(
                report.h3_index,
                report.category,
                since,
                exclude_id=report.id,
            )
            if dupes:
                out.append(self._to_summary(report))
        start = max(page - 1, 0) * page_size
        return out[start : start + page_size]

    def _list_near_threshold(self, *, page: int, page_size: int) -> list[AdminReportSummary]:
        threshold = max(self.cfg.pending_min_reports_per_cell, 1)
        cells = self.reports.list_near_threshold_cells(threshold)
        out: list[AdminReportSummary] = []
        for h3_index in cells:
            for report in self.reports.list_pending_by_h3_index(h3_index):
                out.append(self._to_summary(report))
        start = max(page - 1, 0) * page_size
        return out[start : start + page_size]

    def _run_pipeline(self, h3_index: str) -> bool:
        affected = {h3_index}
        affected.update(h3_service.get_neighbors(h3_index, ring_size=1))
        try:
            AggregationService(self.db).recompute_cells(affected)
            self.db.commit()
            places = PlaceService(self.db).rebuild_places_for_cells(affected)
            place_ids = [p.place_id for p in places]
            ZoneMergeService(self.db).recompute_for_places(place_ids)
            self.db.commit()
            cache_delete_pattern("zones:vp:*")
            cache_delete_pattern("zones:feed*")
            cache_delete_pattern("city:pulse:*")
            cache_delete_pattern(f"reports:pending:{h3_index}")
            return True
        except Exception:
            log.exception("Admin pipeline failed for h3_index=%s", h3_index)
            self.db.rollback()
            return False

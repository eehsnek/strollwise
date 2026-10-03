from __future__ import annotations

from collections.abc import Iterable
from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import desc, func, select
from sqlalchemy.orm import Session

from app.models.report import Report
from app.models.user import User


def _tag_filter_matches(tag_l: str, tags_lower: list[str]) -> bool:
    """Exact token match, or substring for tokens with length >= 3 (e.g. uspf ⊂ uspf campus)."""
    for t in tags_lower:
        if t == tag_l:
            return True
        if len(tag_l) >= 3 and tag_l in t:
            return True
    return False


class ReportRepository:
    def __init__(self, db: Session) -> None:
        self.db = db

    def create(self, report: Report) -> Report:
        self.db.add(report)
        self.db.flush()
        return report

    def has_user_pending_in_h3(self, user_id: UUID, h3_index: str) -> bool:
        stmt = select(func.count()).select_from(Report).where(
            Report.user_id == user_id,
            Report.h3_index == h3_index,
            Report.visibility_status == "pending",
        )
        return int(self.db.scalar(stmt) or 0) > 0

    def latest_user_report_in_h3_since(
        self,
        user_id: UUID,
        h3_index: str,
        since: datetime,
    ) -> Report | None:
        stmt = (
            select(Report)
            .where(
                Report.user_id == user_id,
                Report.h3_index == h3_index,
                Report.created_at >= since,
            )
            .order_by(desc(Report.created_at))
            .limit(1)
        )
        return self.db.execute(stmt).scalars().first()

    def count_user_reports_since(self, user_id: UUID, since: datetime) -> int:
        stmt = select(func.count()).select_from(Report).where(
            Report.user_id == user_id,
            Report.created_at >= since,
        )
        return int(self.db.scalar(stmt) or 0)

    def get_by_id(self, report_id: UUID) -> Report | None:
        return self.db.get(Report, report_id)

    def list_recent(self, limit: int = 50) -> list[Report]:
        stmt = (
            select(Report)
            .where(Report.visibility_status == "visible")
            .order_by(desc(Report.created_at))
            .limit(limit)
        )
        return list(self.db.execute(stmt).scalars())

    def list_by_h3_indexes(self, h3_indexes: Iterable[str]) -> list[Report]:
        h3_list = list(h3_indexes)
        if not h3_list:
            return []
        stmt = (
            select(Report)
            .where(
                Report.h3_index.in_(h3_list),
                Report.visibility_status == "visible",
            )
            .order_by(desc(Report.created_at))
        )
        return list(self.db.execute(stmt).scalars())

    def list_pending_by_h3_index(self, h3_index: str) -> list[Report]:
        stmt = (
            select(Report)
            .where(
                Report.h3_index == h3_index,
                Report.visibility_status == "pending",
            )
            .order_by(desc(Report.created_at))
        )
        return list(self.db.execute(stmt).scalars())

    def list_in_viewport_with_tag(
        self,
        min_lat: float,
        max_lat: float,
        min_lng: float,
        max_lng: float,
        tag: str,
        *,
        limit: int = 120,
        scan_cap: int = 500,
    ) -> list[Report]:
        """Reports in a lat/lng box with pending or visible status; tag matches a token or substring."""
        lo_lat, hi_lat = (min_lat, max_lat) if min_lat <= max_lat else (max_lat, min_lat)
        lo_lng, hi_lng = (min_lng, max_lng) if min_lng <= max_lng else (max_lng, min_lng)
        tag_l = tag.strip().lower()
        stmt = (
            select(Report)
            .where(
                Report.latitude_raw >= lo_lat,
                Report.latitude_raw <= hi_lat,
                Report.longitude_raw >= lo_lng,
                Report.longitude_raw <= hi_lng,
                Report.visibility_status.in_(("pending", "visible")),
            )
            .order_by(desc(Report.created_at))
            .limit(scan_cap)
        )
        rows = list(self.db.execute(stmt).scalars())
        out: list[Report] = []
        for report in rows:
            tags = [str(t).lower() for t in (report.tags_json or [])]
            if _tag_filter_matches(tag_l, tags):
                out.append(report)
            if len(out) >= limit:
                break
        return out

    def list_for_user(self, user_id: UUID, *, limit: int = 20) -> list[Report]:
        stmt = (
            select(Report)
            .where(Report.user_id == user_id)
            .order_by(desc(Report.created_at))
            .limit(limit)
        )
        return list(self.db.execute(stmt).scalars())

    def count_grouped_by_visibility(self, user_id: UUID) -> dict[str, int]:
        stmt = (
            select(Report.visibility_status, func.count())
            .where(Report.user_id == user_id)
            .group_by(Report.visibility_status)
        )
        rows = self.db.execute(stmt).all()
        return {str(status): int(c) for status, c in rows}

    def count_visible_in_category(self, user_id: UUID, category: str) -> int:
        cat = category.strip().lower()
        stmt = select(func.count()).select_from(Report).where(
            Report.user_id == user_id,
            Report.visibility_status == "visible",
            Report.category == cat,
        )
        return int(self.db.scalar(stmt) or 0)

    def list_own_pending_in_viewport(
        self,
        user_id: UUID,
        min_lat: float,
        max_lat: float,
        min_lng: float,
        max_lng: float,
        *,
        limit: int = 80,
    ) -> list[Report]:
        """Pending reports by this user in a lat/lng box (private draft pins on map)."""
        lo_lat, hi_lat = (min_lat, max_lat) if min_lat <= max_lat else (max_lat, min_lat)
        lo_lng, hi_lng = (min_lng, max_lng) if min_lng <= max_lng else (max_lng, min_lng)
        stmt = (
            select(Report)
            .where(
                Report.user_id == user_id,
                Report.visibility_status == "pending",
                Report.latitude_raw >= lo_lat,
                Report.latitude_raw <= hi_lat,
                Report.longitude_raw >= lo_lng,
                Report.longitude_raw <= hi_lng,
            )
            .order_by(desc(Report.created_at))
            .limit(limit)
        )
        return list(self.db.execute(stmt).scalars())

    def list_admin(
        self,
        *,
        visibility_status: str | None = None,
        h3_index: str | None = None,
        page: int = 1,
        page_size: int = 50,
    ) -> tuple[list[Report], int]:
        stmt = select(Report)
        count_stmt = select(func.count()).select_from(Report)
        if visibility_status:
            stmt = stmt.where(Report.visibility_status == visibility_status)
            count_stmt = count_stmt.where(Report.visibility_status == visibility_status)
        if h3_index:
            stmt = stmt.where(Report.h3_index == h3_index)
            count_stmt = count_stmt.where(Report.h3_index == h3_index)
        total = int(self.db.scalar(count_stmt) or 0)
        offset = max(page - 1, 0) * page_size
        stmt = stmt.order_by(desc(Report.created_at)).offset(offset).limit(page_size)
        return list(self.db.execute(stmt).scalars()), total

    def list_by_ids(self, report_ids: list[UUID]) -> list[Report]:
        if not report_ids:
            return []
        stmt = select(Report).where(Report.id.in_(report_ids))
        return list(self.db.execute(stmt).scalars())

    def list_by_h3_and_category_since(
        self,
        h3_index: str,
        category: str,
        since: datetime,
        *,
        exclude_id: UUID | None = None,
    ) -> list[Report]:
        stmt = select(Report).where(
            Report.h3_index == h3_index,
            Report.category == category.lower(),
            Report.created_at >= since,
        )
        if exclude_id:
            stmt = stmt.where(Report.id != exclude_id)
        stmt = stmt.order_by(desc(Report.created_at))
        return list(self.db.execute(stmt).scalars())

    def list_near_threshold_cells(self, threshold: int) -> list[str]:
        """H3 cells with pending reports from fewer than threshold distinct contributors."""
        stmt = (
            select(Report.h3_index)
            .where(Report.visibility_status == "pending")
            .group_by(Report.h3_index)
            .having(func.count(func.distinct(Report.user_id)) < threshold)
        )
        return [str(row[0]) for row in self.db.execute(stmt).all()]

    def count_by_visibility(self, status: str) -> int:
        stmt = select(func.count()).select_from(Report).where(
            Report.visibility_status == status
        )
        return int(self.db.scalar(stmt) or 0)

    def count_distinct_contributors_in_h3(
        self, h3_index: str, *, visibility_status: str | None = None
    ) -> int:
        stmt = select(func.count(func.distinct(Report.user_id))).where(
            Report.h3_index == h3_index
        )
        if visibility_status:
            stmt = stmt.where(Report.visibility_status == visibility_status)
        return int(self.db.scalar(stmt) or 0)

    def count_reports_per_day(self, days: int = 30) -> list[tuple[str, int]]:
        since = datetime.now(timezone.utc) - timedelta(days=days)
        dialect = self.db.get_bind().dialect.name
        if dialect == "postgresql":
            day_expr = func.to_char(Report.created_at, "YYYY-MM-DD")
        else:
            day_expr = func.strftime("%Y-%m-%d", Report.created_at)
        stmt = (
            select(day_expr, func.count())
            .where(Report.created_at >= since)
            .group_by(day_expr)
            .order_by(day_expr)
        )
        return [(str(d), int(c)) for d, c in self.db.execute(stmt).all() if d is not None]

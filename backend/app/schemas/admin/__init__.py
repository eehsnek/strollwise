from __future__ import annotations

from datetime import datetime
from enum import Enum
from uuid import UUID

from pydantic import BaseModel, Field


class ModerationQueueFilter(str, Enum):
    PENDING = "pending"
    FLAGGED = "flagged"
    VISIBLE = "visible"
    REMOVED = "removed"
    DUPLICATES = "duplicates"
    NEAR_THRESHOLD = "near_threshold"
    ALL = "all"


class ModerationAction(str, Enum):
    APPROVE = "approve"
    REJECT = "reject"
    FLAG = "flag"
    KEEP_PENDING = "keep_pending"


class AdminReportSummary(BaseModel):
    id: UUID
    h3_index: str
    category: str
    tags: list[str] = Field(default_factory=list)
    note_text: str | None = None
    visibility_status: str
    confidence_score: float = 0.0
    contributor_count: int = 0
    duplicate_count: int = 0
    created_at: datetime
    image_url: str | None = None


class AdminCellContext(BaseModel):
    h3_index: str
    pending_count: int
    visible_count: int
    flagged_count: int
    distinct_contributors: int
    top_category: str | None = None
    category_agreement: float = 0.0
    threshold: int
    threshold_met: bool


class AdminReportDetail(AdminReportSummary):
    cell_context: AdminCellContext


class AdminReportListResponse(BaseModel):
    items: list[AdminReportSummary]
    total: int
    page: int
    page_size: int


class ModerationBulkRequest(BaseModel):
    report_ids: list[UUID]
    action: ModerationAction


class ModerationBulkResult(BaseModel):
    updated: int
    failed: list[UUID] = Field(default_factory=list)


class ModerationActionResult(BaseModel):
    report: AdminReportSummary
    cell_context: AdminCellContext
    pipeline_triggered: bool = False


class AdminZoneSummary(BaseModel):
    zone_id: UUID
    display_name: str
    slug: str
    traveler_mix: str | None = None
    function_type: str | None = None
    live_status: str
    confidence_score: float
    report_count: int
    is_active: bool
    lifecycle_state: str


class AdminZoneValidation(BaseModel):
    zone_id: UUID
    display_name: str
    total_signals: int
    matching_signals: int
    confidence: float
    top_category: str | None = None
    last_updated: datetime | None = None
    lifecycle_state: str


class AdminZoneUpdate(BaseModel):
    display_name: str | None = None
    summary: str | None = None
    live_status: str | None = None
    is_active: bool | None = None


class AdminUserSummary(BaseModel):
    id: UUID
    email: str
    display_name: str | None = None
    user_type: str | None = None
    traveler_type: str | None = None
    is_active: bool
    is_admin: bool
    report_count: int = 0
    created_at: datetime


class AdminUserUpdate(BaseModel):
    is_active: bool | None = None
    is_admin: bool | None = None


class AdminUserListResponse(BaseModel):
    items: list[AdminUserSummary]
    total: int
    page: int
    page_size: int


class AdminUserContributions(BaseModel):
    user_id: UUID
    total_reports: int
    visible_reports: int
    pending_reports: int
    flagged_reports: int
    badges: list[str] = Field(default_factory=list)


class AdminAuditEntry(BaseModel):
    id: UUID
    actor_user_id: UUID | None = None
    action_type: str
    entity_type: str
    entity_id: str | None = None
    payload_json: dict | None = None
    created_at: datetime


class AdminAuditListResponse(BaseModel):
    items: list[AdminAuditEntry]
    total: int
    page: int
    page_size: int


class AdminAnalyticsOverview(BaseModel):
    pending_reports: int
    flagged_reports: int
    visible_reports: int
    active_zones: int
    local_contributors: int
    international_contributors: int
    domestic_contributors: int
    zones_emerging: int
    zones_defined: int
    city_pulse: dict


class AdminCatalogEntry(BaseModel):
    zone_id: str
    zone_name: str
    city: str
    zone_type: str
    radius_km: float
    center_lat: float
    center_lng: float
    characteristics: list[str] = Field(default_factory=list)
    default_local_ratio: float
    is_active: bool = True


class AdminCatalogCreate(BaseModel):
    zone_id: str
    zone_name: str
    city: str
    zone_type: str
    radius_km: float
    center_lat: float
    center_lng: float
    characteristics: list[str] = Field(default_factory=list)
    default_local_ratio: float = 0.5
    is_active: bool = True


class AdminCatalogUpdate(BaseModel):
    zone_name: str | None = None
    city: str | None = None
    zone_type: str | None = None
    radius_km: float | None = None
    center_lat: float | None = None
    center_lng: float | None = None
    characteristics: list[str] | None = None
    default_local_ratio: float | None = None
    is_active: bool | None = None


class AdminSystemConfig(BaseModel):
    pending_min_reports_per_cell: int
    pending_agreement_ratio: float
    report_cooldown_hours_per_cell: int
    report_max_per_user_per_hour: int
    h3_resolution: int


class AdminSystemConfigUpdate(BaseModel):
    pending_min_reports_per_cell: int | None = None
    pending_agreement_ratio: float | None = None
    report_cooldown_hours_per_cell: int | None = None
    report_max_per_user_per_hour: int | None = None
    h3_resolution: int | None = None


class AdminPipelineResult(BaseModel):
    job: str
    started_at: datetime
    affected_counts: dict[str, int]
    message: str


class AdminDashboardStats(BaseModel):
    pending_reports: int
    flagged_reports: int
    active_zones: int
    total_users: int
    local_contributor_ratio: float
    reports_last_30_days: list[dict[str, int | str]] = Field(default_factory=list)

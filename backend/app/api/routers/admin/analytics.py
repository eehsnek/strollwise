from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from fastapi.responses import PlainTextResponse
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin
from app.core.database import get_db
from app.models.user import User
from app.schemas.admin import AdminAnalyticsOverview
from app.services.admin_service import AdminService

router = APIRouter(prefix="/analytics", tags=["admin"])


@router.get("/overview", response_model=AdminAnalyticsOverview)
def analytics_overview(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminAnalyticsOverview:
    return AdminService(db).analytics_overview()


@router.get("/export/reports")
def export_reports(
    fmt: str = Query(default="json", pattern="^(json|csv)$"),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> PlainTextResponse:
    content = AdminService(db).export_reports(fmt=fmt)
    media = "text/csv" if fmt == "csv" else "application/json"
    return PlainTextResponse(content, media_type=media)


@router.get("/export/zones")
def export_zones(
    fmt: str = Query(default="json", pattern="^(json|csv)$"),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> PlainTextResponse:
    content = AdminService(db).export_zones(fmt=fmt)
    media = "text/csv" if fmt == "csv" else "application/json"
    return PlainTextResponse(content, media_type=media)


@router.get("/export/audit")
def export_audit(
    fmt: str = Query(default="json", pattern="^(json|csv)$"),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> PlainTextResponse:
    content = AdminService(db).export_audit(fmt=fmt)
    media = "text/csv" if fmt == "csv" else "application/json"
    return PlainTextResponse(content, media_type=media)

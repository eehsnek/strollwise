from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models.user import User
from app.repositories.zone_repository import ZoneRepository
from app.models.enums import VisibilityStatus
from app.schemas.report import AggregationFeedback, PlaceTagMarker, ReportCreate, ReportPublic
from app.schemas.report import ReportSubmissionResponse
from app.schemas.visit_pin import VisitPinCreate, VisitPinPublic
from app.services.report_service import ReportService, ReportValidationError
from app.services.visit_pin_service import VisitPinService

router = APIRouter(prefix="/reports", tags=["reports"])


@router.post(
    "",
    response_model=ReportSubmissionResponse,
    status_code=status.HTTP_201_CREATED,
)
def submit_report(
    payload: ReportCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> ReportSubmissionResponse:
    try:
        result = ReportService(db).create_report(payload, current_user)
    except ReportValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)
        )
    report_data = ReportPublic.model_validate(result.report).model_dump(by_alias=True)
    return ReportSubmissionResponse(
        **report_data,
        aggregation=AggregationFeedback.model_validate(result.aggregation),
    )


@router.post(
    "/my-visit-pins",
    response_model=VisitPinPublic,
    status_code=status.HTTP_201_CREATED,
)
def create_my_visit_pin(
    payload: VisitPinCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> VisitPinPublic:
    """Drop a private visit pin — only you can see it on the map."""
    pin = VisitPinService(db).create_from_payload(current_user, payload)
    return VisitPinPublic.model_validate(pin)


@router.get("/my-visit-pins", response_model=list[VisitPinPublic])
def my_visit_pins(
    min_lat: float = Query(..., ge=-90.0, le=90.0),
    max_lat: float = Query(..., ge=-90.0, le=90.0),
    min_lng: float = Query(..., ge=-180.0, le=180.0),
    max_lng: float = Query(..., ge=-180.0, le=180.0),
    limit: int = Query(120, ge=1, le=300),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[VisitPinPublic]:
    pins = VisitPinService(db).list_viewport(
        current_user.id,
        min_lat,
        max_lat,
        min_lng,
        max_lng,
        limit=limit,
    )
    return [VisitPinPublic.model_validate(p) for p in pins]


@router.get("/my-visit-history", response_model=list[VisitPinPublic])
def my_visit_history(
    limit: int = Query(40, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[VisitPinPublic]:
    pins = VisitPinService(db).list_history(current_user.id, limit=limit)
    return [VisitPinPublic.model_validate(p) for p in pins]


@router.get("/my-pending-pins", response_model=list[PlaceTagMarker])
def my_pending_tag_pins(
    min_lat: float = Query(..., ge=-90.0, le=90.0),
    max_lat: float = Query(..., ge=-90.0, le=90.0),
    min_lng: float = Query(..., ge=-180.0, le=180.0),
    max_lng: float = Query(..., ge=-180.0, le=180.0),
    limit: int = Query(80, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[PlaceTagMarker]:
    """Your pending tags in the viewport (shown only to you until validated)."""
    reports = ReportService(db).list_own_pending_pins(
        current_user.id,
        min_lat,
        max_lat,
        min_lng,
        max_lng,
        limit=limit,
    )
    return [
        PlaceTagMarker(
            id=r.id,
            latitude=r.latitude_raw,
            longitude=r.longitude_raw,
            validated=False,
        )
        for r in reports
    ]


@router.get("/place-markers", response_model=list[PlaceTagMarker])
def place_tag_markers(
    min_lat: float = Query(..., ge=-90.0, le=90.0),
    max_lat: float = Query(..., ge=-90.0, le=90.0),
    min_lng: float = Query(..., ge=-180.0, le=180.0),
    max_lng: float = Query(..., ge=-180.0, le=180.0),
    tag: str = Query("uspf", min_length=1, max_length=32),
    limit: int = Query(120, ge=1, le=300),
    db: Session = Depends(get_db),
) -> list[PlaceTagMarker]:
    """Map pins for reports that include a tag token (default USPF campus)."""
    tag_key = tag.strip().lower()
    reports = ReportService(db).list_place_markers(
        min_lat, max_lat, min_lng, max_lng, tag_key, limit=limit
    )
    return [
        PlaceTagMarker(
            id=r.id,
            latitude=r.latitude_raw,
            longitude=r.longitude_raw,
            validated=r.visibility_status == VisibilityStatus.VISIBLE.value,
        )
        for r in reports
    ]


@router.get("/feed", response_model=list[ReportPublic])
def report_feed(
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
) -> list[ReportPublic]:
    reports = ReportService(db).recent_feed(limit)
    return [ReportPublic.model_validate(r) for r in reports]


@router.get("/by-zone/{zone_id}", response_model=list[ReportPublic])
def reports_by_zone(
    zone_id: UUID,
    db: Session = Depends(get_db),
) -> list[ReportPublic]:
    zone = ZoneRepository(db).get(zone_id)
    if zone is None:
        raise HTTPException(status_code=404, detail="Zone not found")
    reports = ReportService(db).reports_in_zone(zone.source_h3_indexes_json or [])
    return [ReportPublic.model_validate(r) for r in reports]

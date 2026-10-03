from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin
from app.core.database import get_db
from app.models.user import User
from app.schemas.admin import AdminZoneSummary, AdminZoneUpdate, AdminZoneValidation
from app.services.admin_service import AdminService

router = APIRouter(prefix="/zones", tags=["admin"])


@router.get("", response_model=list[AdminZoneSummary])
def list_zones(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> list[AdminZoneSummary]:
    return AdminService(db).list_zones()


@router.get("/{zone_id}/validation", response_model=AdminZoneValidation)
def zone_validation(
    zone_id: UUID,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminZoneValidation:
    result = AdminService(db).zone_validation(zone_id)
    if result is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Zone not found")
    return result


@router.get("/{zone_id}/history")
def zone_history(
    zone_id: UUID,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> list[dict]:
    if AdminService(db).zones.get(zone_id) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Zone not found")
    return AdminService(db).zone_history(zone_id)


@router.patch("/{zone_id}", response_model=AdminZoneSummary)
def update_zone(
    zone_id: UUID,
    payload: AdminZoneUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminZoneSummary:
    result = AdminService(db).update_zone(zone_id, payload)
    if result is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Zone not found")
    return result

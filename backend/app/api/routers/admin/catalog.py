from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin
from app.core.database import get_db
from app.models.user import User
from app.schemas.admin import AdminAuditListResponse, AdminCatalogCreate, AdminCatalogEntry, AdminCatalogUpdate
from app.services.admin_service import AdminService

router = APIRouter(prefix="/catalog", tags=["admin"])


@router.get("/zones", response_model=list[AdminCatalogEntry])
def list_catalog(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> list[AdminCatalogEntry]:
    return AdminService(db).list_catalog()


@router.post("/zones", response_model=AdminCatalogEntry, status_code=status.HTTP_201_CREATED)
def create_catalog_entry(
    payload: AdminCatalogCreate,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminCatalogEntry:
    return AdminService(db).create_catalog(payload)


@router.patch("/zones/{zone_id}", response_model=AdminCatalogEntry)
def update_catalog_entry(
    zone_id: str,
    payload: AdminCatalogUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminCatalogEntry:
    result = AdminService(db).update_catalog(zone_id, payload)
    if result is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Catalog entry not found")
    return result


@router.delete("/zones/{zone_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_catalog_entry(
    zone_id: str,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> Response:
    if not AdminService(db).delete_catalog(zone_id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Catalog entry not found")
    return Response(status_code=status.HTTP_204_NO_CONTENT)

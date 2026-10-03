from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin
from app.core.database import get_db
from app.models.user import User
from app.schemas.admin import AdminPipelineResult
from app.services.admin_service import AdminService

router = APIRouter(prefix="/pipeline", tags=["admin"])


class RebuildCellsRequest(BaseModel):
    h3_indexes: list[str] | None = None


@router.post("/rebuild-cells", response_model=AdminPipelineResult)
def rebuild_cells(
    payload: RebuildCellsRequest | None = None,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminPipelineResult:
    indexes = payload.h3_indexes if payload else None
    return AdminService(db).rebuild_cells(indexes)


@router.post("/rebuild-places", response_model=AdminPipelineResult)
def rebuild_places(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminPipelineResult:
    return AdminService(db).rebuild_places()


@router.post("/rebuild-zones", response_model=AdminPipelineResult)
def rebuild_zones(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminPipelineResult:
    return AdminService(db).rebuild_zones()


@router.post("/rebuild-all", response_model=AdminPipelineResult)
def rebuild_all(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminPipelineResult:
    return AdminService(db).rebuild_all()


@router.post("/invalidate-cache", response_model=AdminPipelineResult)
def invalidate_cache(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminPipelineResult:
    return AdminService(db).invalidate_cache()

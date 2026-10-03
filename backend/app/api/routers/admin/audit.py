from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin
from app.core.database import get_db
from app.models.user import User
from app.schemas.admin import AdminAuditListResponse
from app.services.admin_service import AdminService

router = APIRouter(prefix="/audit", tags=["admin"])


@router.get("", response_model=AdminAuditListResponse)
def list_audit(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=50, ge=1, le=200),
    action_type: str | None = Query(default=None),
    entity_type: str | None = Query(default=None),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminAuditListResponse:
    return AdminService(db).list_audit(
        page=page,
        page_size=page_size,
        action_type=action_type,
        entity_type=entity_type,
    )

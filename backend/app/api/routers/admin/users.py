from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin
from app.core.database import get_db
from app.models.user import User
from app.schemas.admin import (
    AdminUserContributions,
    AdminUserListResponse,
    AdminUserSummary,
    AdminUserUpdate,
)
from app.services.admin_service import AdminService

router = APIRouter(prefix="/users", tags=["admin"])


@router.get("", response_model=AdminUserListResponse)
def list_users(
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=50, ge=1, le=200),
    search: str | None = Query(default=None),
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminUserListResponse:
    return AdminService(db).list_users(page=page, page_size=page_size, search=search)


@router.patch("/{user_id}", response_model=AdminUserSummary)
def update_user(
    user_id: UUID,
    payload: AdminUserUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminUserSummary:
    result = AdminService(db).update_user(user_id, payload)
    if result is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return result


@router.get("/{user_id}/contributions", response_model=AdminUserContributions)
def user_contributions(
    user_id: UUID,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminUserContributions:
    result = AdminService(db).user_contributions(user_id)
    if result is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return result

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin
from app.core.database import get_db
from app.models.user import User
from app.schemas.admin import AdminDashboardStats
from app.services.admin_service import AdminService

router = APIRouter(prefix="/dashboard", tags=["admin"])


@router.get("/stats", response_model=AdminDashboardStats)
def dashboard_stats(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminDashboardStats:
    return AdminService(db).dashboard_stats()

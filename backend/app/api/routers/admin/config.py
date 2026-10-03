from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin
from app.core.database import get_db
from app.models.user import User
from app.schemas.admin import AdminSystemConfig, AdminSystemConfigUpdate
from app.services.system_settings_service import SystemSettingsService

router = APIRouter(prefix="/config", tags=["admin"])


@router.get("", response_model=AdminSystemConfig)
def get_config(
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminSystemConfig:
    data = SystemSettingsService(db).get_config_dict()
    return AdminSystemConfig(**data)


@router.patch("", response_model=AdminSystemConfig)
def update_config(
    payload: AdminSystemConfigUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_admin),
) -> AdminSystemConfig:
    updates = payload.model_dump(exclude_none=True)
    data = SystemSettingsService(db).update_config(updates)
    db.commit()
    return AdminSystemConfig(**data)

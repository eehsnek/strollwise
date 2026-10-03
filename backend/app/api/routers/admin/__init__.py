from __future__ import annotations

from fastapi import APIRouter

from app.api.routers.admin import (
    analytics,
    audit,
    catalog,
    config,
    dashboard,
    events,
    moderation,
    pipeline,
    users,
    zones,
)

router = APIRouter(prefix="/admin", tags=["admin"])

router.include_router(events.router)
router.include_router(dashboard.router)
router.include_router(moderation.router)
router.include_router(zones.router)
router.include_router(users.router)
router.include_router(analytics.router)
router.include_router(catalog.router)
router.include_router(pipeline.router)
router.include_router(config.router)
router.include_router(audit.router)

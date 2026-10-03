from __future__ import annotations

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routers import (
    analytics,
    auth,
    cells,
    geocode,
    places,
    reports,
    uploads,
    users,
    zones,
)
from app.api.routers.admin import router as admin_router
from app.core.config import settings
from app.core.logging import configure_logging

configure_logging()
log = logging.getLogger(__name__)


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        docs_url="/docs",
        redoc_url="/redoc",
    )
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    prefix = settings.api_v1_prefix
    app.include_router(auth.router, prefix=prefix)
    app.include_router(users.router, prefix=prefix)
    app.include_router(reports.router, prefix=prefix)
    app.include_router(zones.router, prefix=prefix)
    app.include_router(cells.router, prefix=prefix)
    app.include_router(places.router, prefix=prefix)
    app.include_router(analytics.router, prefix=prefix)
    app.include_router(uploads.router, prefix=prefix)
    app.include_router(geocode.router, prefix=prefix)
    app.include_router(admin_router, prefix=prefix)

    @app.get("/health", tags=["health"])
    def health_check() -> dict[str, str]:
        return {"status": "ok", "app": settings.app_name, "env": settings.env}

    log.info("%s ready (env=%s)", settings.app_name, settings.env)
    return app


app = create_app()

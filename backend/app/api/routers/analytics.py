from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.repositories.zone_repository import ZoneRepository
from app.schemas.analytics import (
    CityPulse,
    TrendPoint,
    TrendSeries,
    ZoneHistory,
    ZoneHistoryPoint,
)
from app.services.city_pulse_service import CityPulseService

router = APIRouter(prefix="/analytics", tags=["analytics"])


@router.get("/city-pulse", response_model=CityPulse)
def city_pulse(db: Session = Depends(get_db)) -> CityPulse:
    return CityPulseService(db).compute()


@router.get("/trends", response_model=list[TrendSeries])
def trends(db: Session = Depends(get_db)) -> list[TrendSeries]:
    zones = ZoneRepository(db).list_active()
    totals: dict[str, int] = {}
    for zone in zones:
        totals[zone.function_type] = totals.get(zone.function_type, 0) + 1
    points = [TrendPoint(label=k, value=float(v)) for k, v in sorted(totals.items())]
    return [TrendSeries(key="active_zones_by_function", title="Active zones by function", points=points)]


@router.get("/zone/{zone_id}/history", response_model=ZoneHistory)
def zone_history(zone_id: UUID, db: Session = Depends(get_db)) -> ZoneHistory:
    repo = ZoneRepository(db)
    if repo.get(zone_id) is None:
        raise HTTPException(status_code=404, detail="Zone not found")
    snapshots = repo.list_snapshots(zone_id)
    points = [
        ZoneHistoryPoint(
            snapshot_date=s.snapshot_date,
            crowd_level=s.crowd_level,
            local_presence_percent=s.local_presence_percent,
            confidence_score=s.confidence_score,
            report_count=s.report_count,
        )
        for s in snapshots
    ]
    return ZoneHistory(zone_id=str(zone_id), points=points)

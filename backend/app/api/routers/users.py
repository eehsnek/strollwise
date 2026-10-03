from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.api.routers import zones as zones_router
from app.core.database import get_db
from app.models.user import User
from app.repositories.report_repository import ReportRepository
from app.repositories.user_repository import UserRepository
from app.repositories.zone_repository import ZoneRepository
from app.schemas.common import MessageResponse
from app.schemas.report import ReportPublic
from app.schemas.user import (
    ProfileBadge,
    UserContributionsResponse,
    UserContributionStats,
    UserPublic,
    UserUpdate,
)
from app.schemas.zone import ZoneListItem
from app.services.audit_service import AuditService
from app.utils.user_type_utils import apply_user_type_to_user

router = APIRouter(prefix="/users", tags=["users"])


def _contributor_label(approved: int) -> str:
    if approved == 0:
        return "New to sharing"
    if approved < 5:
        return "Active contributor"
    if approved < 25:
        return "Community mapper"
    return "Zone champion"


def _earned_badges(
    repo: ReportRepository, user_id: UUID, submitted: int, approved: int
) -> list[ProfileBadge]:
    badges: list[ProfileBadge] = []
    if submitted >= 1:
        badges.append(ProfileBadge(key="zone_scout", label="Zone Scout"))
    if repo.count_visible_in_category(user_id, "food") >= 1:
        badges.append(ProfileBadge(key="food_finder", label="Food Finder"))
    if repo.count_visible_in_category(user_id, "transport") >= 1:
        badges.append(ProfileBadge(key="transport_helper", label="Transport Helper"))
    if repo.count_visible_in_category(user_id, "safety") >= 1:
        badges.append(ProfileBadge(key="safety_reporter", label="Safety Reporter"))
    if approved >= 5:
        badges.append(ProfileBadge(key="local_guide", label="Local Guide"))
    return badges


@router.get("/me/contributions", response_model=UserContributionsResponse)
def my_contributions(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    limit: int = Query(15, ge=1, le=50),
) -> UserContributionsResponse:
    repo = ReportRepository(db)
    counts = repo.count_grouped_by_visibility(current_user.id)
    approved = int(counts.get("visible", 0))
    pending = int(counts.get("pending", 0))
    submitted = sum(int(v) for v in counts.values())
    recent = repo.list_for_user(current_user.id, limit=limit)
    badges = _earned_badges(repo, current_user.id, submitted, approved)
    return UserContributionsResponse(
        stats=UserContributionStats(
            submitted=submitted,
            approved=approved,
            pending=pending,
        ),
        recent_reports=[ReportPublic.model_validate(r) for r in recent],
        badges=badges,
        contributor_label=_contributor_label(approved),
    )


@router.get("/me", response_model=UserPublic)
def get_me(current_user: User = Depends(get_current_user)) -> UserPublic:
    return UserPublic.model_validate(current_user)


@router.patch("/me", response_model=UserPublic)
def update_me(
    payload: UserUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> UserPublic:
    data = payload.model_dump(exclude_unset=True)
    for key, value in data.items():
        setattr(current_user, key, value)
    if "user_type" in data:
        apply_user_type_to_user(current_user)
    UserRepository(db).save(current_user)
    db.commit()
    db.refresh(current_user)
    return UserPublic.model_validate(current_user)


@router.get("/me/saved-zones", response_model=list[ZoneListItem])
def list_saved_zones(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> list[ZoneListItem]:
    repo = ZoneRepository(db)
    saved = repo.list_saved_by_user(current_user.id)
    items: list[ZoneListItem] = []
    for entry in saved:
        zone = repo.get(entry.zone_id)
        if zone is None:
            continue
        items.append(zones_router._to_list_item(zone))
    return items


@router.post("/me/saved-zones/{zone_id}", response_model=MessageResponse, status_code=status.HTTP_201_CREATED)
def save_zone(
    zone_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> MessageResponse:
    repo = ZoneRepository(db)
    zone = repo.get(zone_id)
    if zone is None:
        raise HTTPException(status_code=404, detail="Zone not found")
    existing = repo.find_saved(current_user.id, zone_id)
    if existing is not None:
        return MessageResponse(message="Zone already saved")
    repo.save_zone(current_user.id, zone_id)
    AuditService(db).record(
        actor_user_id=current_user.id,
        action_type="saved_zone.create",
        entity_type="merged_zone",
        entity_id=zone_id,
    )
    db.commit()
    return MessageResponse(message="Zone saved")


@router.delete("/me/saved-zones/{zone_id}", response_model=MessageResponse)
def unsave_zone(
    zone_id: UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> MessageResponse:
    repo = ZoneRepository(db)
    existing = repo.find_saved(current_user.id, zone_id)
    if existing is None:
        raise HTTPException(status_code=404, detail="Saved zone not found")
    repo.unsave_zone(existing)
    AuditService(db).record(
        actor_user_id=current_user.id,
        action_type="saved_zone.delete",
        entity_type="merged_zone",
        entity_id=zone_id,
    )
    db.commit()
    return MessageResponse(message="Zone removed from saved list")

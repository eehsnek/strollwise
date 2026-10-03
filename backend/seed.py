"""Idempotent seed script for StrollWise.

Creates:
- 20–50 demo users across traveler types
- 300–1000 realistic reports clustered around Cebu City districts
- Runs aggregation, classification, and zone merging end-to-end so the
  demo frontend has immediately useful data.

Usage:
    PYTHONPATH=backend python backend/seed.py
"""
from __future__ import annotations

import random
import sys
from pathlib import Path

# Make `app.*` importable whether seed.py is run from repo root or backend/.
BASE_DIR = Path(__file__).resolve().parent
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))

from datetime import datetime, timedelta, timezone

from faker import Faker
from sqlalchemy import delete
from sqlalchemy.orm import Session

from app.core.database import SessionLocal
from app.core.security import hash_password
from app.models import (
    AuditLog,
    H3CellAggregate,
    Media,
    MergedZone,
    Report,
    SavedZone,
    User,
    ZoneSnapshot,
)
from app.services import h3_service
from app.services.aggregation_service import AggregationService
from app.services.place_service import PlaceService
from app.services.admin_bootstrap import ensure_admin_user
from app.services.zone_merge_service import ZoneMergeService
from app.utils.user_type_utils import apply_user_type_to_user, traveler_type_from_user_type

fake = Faker()
random.seed(7)
Faker.seed(7)

from app.services.zone_catalog import CEBU_ZONE_CATALOG

ADMIN_EMAIL = "admin@strollwise.dev"


def _traveler_bias(local_ratio: float) -> str:
    if local_ratio >= 0.75:
        return "local"
    if local_ratio <= 0.30:
        return "international"
    return "mixed"


def _categories_for(entry) -> list[str]:
    zt = entry.zone_type.upper()
    if zt == "LOCAL":
        return ["food", "transport", "activity"]
    if zt == "INTERNATIONAL":
        return ["food", "activity", "nightlife", "shopping"]
    return ["food", "shopping", "activity", "transport"]


def _tags_for(entry) -> list[str]:
    return list(entry.characteristics[:4]) or ["local_activity"]


def _notes_for(entry) -> list[str]:
    return [
        f"Movement pattern aligned with {entry.zone_name} ({entry.zone_type.lower()}).",
        "Seeded demo tags for thesis map validation.",
    ]


def _seed_district(entry) -> dict:
    bias = _traveler_bias(entry.default_local_ratio)
    return {
        "name": entry.zone_name,
        "center": (entry.center_lat, entry.center_lng),
        "radius": entry.radius_km / 111.0 * 0.08,
        "traveler_bias": bias,
        "categories": _categories_for(entry),
        "tags": _tags_for(entry),
        "notes": _notes_for(entry),
        "peak_hours": [12, 18, 19, 20] if bias != "local" else [7, 8, 12, 17],
    }


# One seed cluster per catalog zone (14 total).
CITY_DISTRICTS = [_seed_district(entry) for entry in CEBU_ZONE_CATALOG]


def clear_tables(db: Session) -> None:
    """Clear demo map/report data. Keeps real registered accounts (non demo*@example.com)."""
    db.execute(delete(ZoneSnapshot))
    db.execute(delete(SavedZone))
    db.execute(delete(AuditLog))
    db.execute(delete(Media))
    db.execute(delete(MergedZone))
    from app.models.place import Place

    db.execute(delete(Place))
    db.execute(delete(H3CellAggregate))
    db.execute(delete(Report))
    # Only remove seeded demo accounts so your defense registrations survive re-seed.
    db.execute(delete(User).where(User.email.like("demo%@example.com")))
    db.commit()


def seed_users(db: Session, count: int = 30) -> list[User]:
    users: list[User] = []
    admin = ensure_admin_user(db)
    users.append(admin)
    thesis_user_types = ["local_resident", "international_visitor", "domestic_traveler"]
    for i in range(count):
        email = f"demo{i}@example.com"
        ut = random.choice(thesis_user_types)
        user = User(
            email=email,
            password_hash=hash_password("supersecret123"),
            display_name=fake.name(),
            traveler_type="mixed",
            user_type=ut,
            country_of_origin=fake.country(),
            city_of_origin=fake.city(),
            nationality=random.choice(["PH", "US", "JP", "KR", "AU", "GB", "DE", None]),
            age_range=random.choice(["18-24", "25-34", "35-44", "45-54"]),
        )
        apply_user_type_to_user(user)
        db.add(user)
        users.append(user)
    db.commit()
    for u in users:
        db.refresh(u)
    return users


def seed_reports(db: Session, users: list[User], target_count: int = 600) -> list[Report]:
    reports: list[Report] = []
    now = datetime.now(timezone.utc).replace(tzinfo=None)  # noqa: UP017
    weight = len(CITY_DISTRICTS) * 20
    for _ in range(target_count):
        district = random.choices(
            CITY_DISTRICTS,
            weights=[weight - i for i in range(len(CITY_DISTRICTS))],
            k=1,
        )[0]
        lat_center, lng_center = district["center"]
        r = district["radius"]
        lat = lat_center + random.uniform(-r, r)
        lng = lng_center + random.uniform(-r, r)
        category = random.choice(district["categories"])
        tags = random.sample(district["tags"], k=min(len(district["tags"]), random.randint(1, 3)))

        # Traveler bias: 70% chance to match district bias, 30% other.
        if random.random() < 0.7:
            traveler_type = district["traveler_bias"]
        else:
            traveler_type = random.choice(["local", "international", "mixed"])

        peak_hours = district.get("peak_hours") or list(range(24))
        day_offset = random.randint(0, 5)
        hour = random.choice(peak_hours if random.random() < 0.75 else list(range(24)))
        created_at = (now - timedelta(days=day_offset)).replace(
            hour=hour,
            minute=random.randint(0, 59),
            second=0,
            microsecond=0,
        )
        h3_index = h3_service.latlng_to_cell(lat, lng, 8)

        user = random.choice(users)
        tt_snap = (
            traveler_type_from_user_type(user.user_type)
            if user.user_type
            else traveler_type
        )
        report = Report(
            user_id=user.id,
            h3_index=h3_index,
            resolution=8,
            latitude_raw=lat,
            longitude_raw=lng,
            category=category,
            tags_json=tags,
            note_text=random.choice(district.get("notes", [None])),
            source_type="user",
            traveler_type_snapshot=tt_snap,
            user_type_snapshot=user.user_type,
            country_of_origin_snapshot=user.country_of_origin,
            city_of_origin_snapshot=user.city_of_origin,
            visibility_status="visible",
            created_at=created_at,
            updated_at=created_at,
        )
        db.add(report)
        reports.append(report)
    db.commit()
    return reports


def recompute_aggregates_and_zones(db: Session, reports: list[Report]) -> None:
    unique_indexes = {r.h3_index for r in reports}
    AggregationService(db).recompute_cells(unique_indexes)
    db.commit()
    PlaceService(db).rebuild_all()
    ZoneMergeService(db).rebuild_all()


def main() -> None:
    with SessionLocal() as db:
        print("Clearing existing seed data (keeping registered accounts)…")
        clear_tables(db)

        print("Seeding demo users…")
        users = seed_users(db, count=30)

        print("Seeding reports…")
        reports = seed_reports(db, users, target_count=600)

        print("Recomputing aggregates + publishing per-cell zones…")
        recompute_aggregates_and_zones(db, reports)

        ensure_admin_user(db)
        print(f"Admin account ready: {ADMIN_EMAIL} / admin123456")

        zone_count = db.query(MergedZone).count()
        cell_count = db.query(H3CellAggregate).count()
        print(
            f"Seeded {len(users)} users, {len(reports)} reports, "
            f"{cell_count} H3 cells, {zone_count} map zones."
        )


if __name__ == "__main__":
    main()

"""Ensure the seeded admin account exists with admin privileges."""
from __future__ import annotations

from sqlalchemy.orm import Session

from app.core.security import hash_password
from app.models.user import User
from app.repositories.user_repository import UserRepository
from app.utils.user_type_utils import apply_user_type_to_user

ADMIN_EMAIL = "admin@strollwise.dev"
LEGACY_ADMIN_EMAIL = "admin@strollwise.local"
ADMIN_PASSWORD = "admin123456"


def ensure_admin_user(db: Session) -> User:
    """Create or repair the default admin account (idempotent)."""
    repo = UserRepository(db)
    admin = repo.get_by_email(ADMIN_EMAIL)
    legacy = repo.get_by_email(LEGACY_ADMIN_EMAIL)

    if legacy is not None and admin is None:
        legacy.email = ADMIN_EMAIL
        admin = legacy
    elif admin is None:
        admin = User(
            email=ADMIN_EMAIL,
            password_hash=hash_password(ADMIN_PASSWORD),
            display_name="StrollWise Admin",
            traveler_type="local",
            user_type="local_resident",
            country_of_origin="Philippines",
            city_of_origin="Cebu City",
            is_admin=True,
            is_active=True,
            accepted_research_consent=True,
        )
        apply_user_type_to_user(admin)
        db.add(admin)
    else:
        admin.password_hash = hash_password(ADMIN_PASSWORD)

    admin.is_admin = True
    admin.is_active = True
    repo.save(admin)
    db.commit()
    db.refresh(admin)
    return admin

"""Re-seed must not delete manually registered accounts."""
from __future__ import annotations

from app.core.security import hash_password
from app.models.user import User
from app.utils.user_type_utils import apply_user_type_to_user
from seed import clear_tables, seed_users


def test_clear_tables_keeps_registered_user(db_session):
    db = db_session
    registered = User(
        email="defense.panel@university.edu",
        password_hash=hash_password("supersecret123"),
        display_name="Panel User",
        traveler_type="mixed",
        user_type="local_resident",
        country_of_origin="Philippines",
        city_of_origin="Cebu City",
    )
    apply_user_type_to_user(registered)
    db.add(registered)
    db.commit()
    db.refresh(registered)

    clear_tables(db)
    seed_users(db, count=2)

    kept = db.query(User).filter(User.email == "defense.panel@university.edu").one_or_none()
    assert kept is not None
    assert kept.display_name == "Panel User"

    demo_count = (
        db.query(User).filter(User.email.like("demo%@example.com")).count()
    )
    assert demo_count == 2

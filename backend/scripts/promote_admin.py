"""Promote an existing user to admin.

Usage:
    cd backend && PYTHONPATH=. python3 scripts/promote_admin.py user@example.com
    # macOS: ./scripts/promote_admin.sh user@example.com
"""
from __future__ import annotations

import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))

from app.core.database import SessionLocal
from app.repositories.user_repository import UserRepository
from app.services.admin_bootstrap import ADMIN_EMAIL, ensure_admin_user


def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: python scripts/promote_admin.py <email>")
        sys.exit(1)

    email = sys.argv[1].strip().lower()
    with SessionLocal() as db:
        if email == ADMIN_EMAIL:
            ensure_admin_user(db)
            print(f"Repaired default admin: {ADMIN_EMAIL}")
            return

        user = UserRepository(db).get_by_email(email)
        if user is None:
            print(f"No user found with email {email}")
            sys.exit(1)
        user.is_admin = True
        user.is_active = True
        UserRepository(db).save(user)
        db.commit()
        print(f"Promoted {email} to admin.")


if __name__ == "__main__":
    main()

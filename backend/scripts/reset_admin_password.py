"""Reset the seeded admin password.

Usage:
    cd backend && PYTHONPATH=. python3 scripts/reset_admin_password.py
    # macOS: ./scripts/reset_admin.sh
"""
from __future__ import annotations

import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))

from app.core.database import SessionLocal
from app.services.admin_bootstrap import ADMIN_EMAIL, ADMIN_PASSWORD, ensure_admin_user


def main() -> None:
    with SessionLocal() as db:
        ensure_admin_user(db)
        print(f"Reset password for {ADMIN_EMAIL} (password: {ADMIN_PASSWORD})")


if __name__ == "__main__":
    main()

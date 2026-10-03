"""Registration user_type ↔ legacy traveler_type and aggregation buckets."""

from __future__ import annotations

from app.models.report import Report
from app.models.user import User

ALLOWED_USER_TYPES = frozenset(
    {"local_resident", "international_visitor", "domestic_traveler"}
)


def traveler_type_from_user_type(user_type: str | None) -> str:
    """Map thesis user_type to existing traveler_type for backward compatibility."""
    if not user_type:
        return "mixed"
    key = user_type.strip().lower()
    if key == "international_visitor":
        return "international"
    if key in ("local_resident", "domestic_traveler"):
        return "local"
    return "mixed"


def apply_user_type_to_user(user: User) -> None:
    """Keep traveler_type aligned when user_type is set."""
    user.traveler_type = traveler_type_from_user_type(user.user_type)


def report_counts_local_international(report: Report) -> tuple[bool, bool]:
    """Return (is_local, is_intl) for H3 aggregation; at most one True for typed rows."""
    ut = (report.user_type_snapshot or "").strip().lower()
    if ut == "international_visitor":
        return False, True
    if ut in ("local_resident", "domestic_traveler"):
        return True, False
    if ut:
        return False, False
    tt = (report.traveler_type_snapshot or "").strip().lower()
    return tt == "local", tt == "international"

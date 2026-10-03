"""Traveler mix rollup for zones (local / mixed / international)."""
from __future__ import annotations

from app.models.enums import BehaviorType

LOCAL_THRESHOLD = 0.70
INTERNATIONAL_THRESHOLD = 0.70


def behavior_to_traveler_mix(behavior_type: str) -> str:
    if behavior_type == BehaviorType.LOCAL_AREA.value:
        return "local"
    if behavior_type == BehaviorType.TOURIST_AREA.value:
        return "international"
    return "mixed"


def traveler_mix_from_counts(
    local_count: int, international_count: int
) -> str:
    total = local_count + international_count
    if total == 0:
        return "mixed"
    local_ratio = local_count / total
    intl_ratio = international_count / total
    if local_ratio >= LOCAL_THRESHOLD:
        return "local"
    if intl_ratio >= INTERNATIONAL_THRESHOLD:
        return "international"
    return "mixed"

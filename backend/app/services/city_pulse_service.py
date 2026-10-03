"""Aggregates active zones into a city-level pulse summary."""
from __future__ import annotations

from collections import Counter

from sqlalchemy.orm import Session

from app.core.cache import cache_get, cache_set
from app.core.config import settings
from app.repositories.zone_repository import ZoneRepository
from app.schemas.analytics import CityPulse
from app.utils.time_utils import label_for_peak_hours

_CACHE_KEY = "city:pulse:summary"


class CityPulseService:
    def __init__(self, db: Session) -> None:
        self.db = db
        self.zones = ZoneRepository(db)

    def compute(self) -> CityPulse:
        cached = cache_get(_CACHE_KEY)
        if cached is not None:
            return CityPulse(**cached)

        active = self.zones.list_active()
        if not active:
            pulse = CityPulse(
                city_activity="quiet",
                crowd_level_percent=0.0,
                local_presence_percent=0.0,
                peak_time_window=None,
                top_active_categories=[],
                active_zone_count=0,
            )
        else:
            total_crowd = sum(z.crowd_level for z in active)
            avg_crowd = total_crowd / len(active)
            avg_local = sum(z.local_presence_percent for z in active) / len(active)
            category_counts: Counter[str] = Counter()
            peak_labels: Counter[str] = Counter()
            for zone in active:
                if zone.function_type:
                    category_counts[zone.function_type] += 1
                if zone.peak_time_label:
                    peak_labels[zone.peak_time_label] += 1
            top_categories = [c for c, _ in category_counts.most_common(5) if c]

            # If zones expose peak_hours, we could compute a fine-grained label; fall back to the most common textual label.
            peak_label = peak_labels.most_common(1)[0][0] if peak_labels else label_for_peak_hours([])
            pulse = CityPulse(
                city_activity=_activity_bucket(avg_crowd, len(active)),
                crowd_level_percent=round(avg_crowd * 100, 1),
                local_presence_percent=round(avg_local, 1),
                peak_time_window=peak_label,
                top_active_categories=top_categories,
                active_zone_count=len(active),
            )

        cache_set(_CACHE_KEY, pulse.model_dump(mode="json"), settings.cache_ttl_pulse_seconds)
        return pulse


def _activity_bucket(avg_crowd: float, zone_count: int) -> str:
    if zone_count == 0:
        return "quiet"
    score = avg_crowd + (zone_count / 40.0)
    if score >= 1.3:
        return "bustling"
    if score >= 0.8:
        return "high"
    if score >= 0.4:
        return "moderate"
    return "quiet"

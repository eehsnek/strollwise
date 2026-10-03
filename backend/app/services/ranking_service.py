"""Scoring for the built-in filters (Popular Now, Local Picks, Food, etc.)."""
from __future__ import annotations

import heapq
from collections.abc import Iterable

from app.models.enums import BehaviorType, FunctionType
from app.models.merged_zone import MergedZone
from app.utils.geo_utils import haversine_km
from app.utils.traveler_mix_utils import behavior_to_traveler_mix


def _zone_traveler_mix(zone: MergedZone) -> str:
    if zone.traveler_mix:
        return zone.traveler_mix
    return behavior_to_traveler_mix(zone.behavior_type)


def _zone_place_type(zone: MergedZone) -> str | None:
    return getattr(zone, "_place_type", None)


class RankingService:
    FILTERS = {
        "for_you",
        "popular_now",
        "local_picks",
        "food",
        "school",
        "transport",
        "commercial",
        "tourist",
        "safe_areas",
    }

    @classmethod
    def apply_viewport_filters(
        cls,
        zones: Iterable[MergedZone],
        *,
        filter_key: str | None = None,
        traveler_mix: str | None = None,
        place_type: str | None = None,
        user_lat: float | None = None,
        user_lng: float | None = None,
        limit: int | None = None,
    ) -> list[MergedZone]:
        """Filter by traveler mix and/or place type, then rank."""
        zones_list = list(zones)
        if traveler_mix:
            mix = traveler_mix.lower()
            zones_list = [z for z in zones_list if _zone_traveler_mix(z) == mix]
        if place_type:
            pt = place_type.lower()
            zones_list = [
                z
                for z in zones_list
                if (_zone_place_type(z) or "").lower() == pt
            ]
        return cls.rank(
            zones_list,
            filter_key=filter_key,
            user_lat=user_lat,
            user_lng=user_lng,
            limit=limit,
        )

    @classmethod
    def rank(
        cls,
        zones: Iterable[MergedZone],
        *,
        filter_key: str | None,
        user_lat: float | None = None,
        user_lng: float | None = None,
        limit: int | None = None,
    ) -> list[MergedZone]:
        zones_list = list(zones)
        if filter_key is None:
            if limit is None:
                return sorted(
                    zones_list, key=lambda z: float(z.priority_score or 0), reverse=True
                )
            return heapq.nlargest(
                min(limit, len(zones_list)),
                zones_list,
                key=lambda z: float(z.priority_score or 0),
            )

        key = filter_key.lower()
        if key not in cls.FILTERS:

            def priority_only(z: MergedZone) -> float:
                return float(z.priority_score or 0)

            if limit is None:
                return sorted(zones_list, key=priority_only, reverse=True)
            return heapq.nlargest(min(limit, len(zones_list)), zones_list, key=priority_only)

        def score(zone: MergedZone) -> float:
            base = float(zone.priority_score or 0)
            if key == "popular_now":
                base += zone.crowd_level * 30 + zone.report_count * 0.25
            elif key == "local_picks":
                base += zone.local_presence_percent * 0.8
                if _zone_traveler_mix(zone) == "local":
                    base += 20
            elif key == "food":
                if _zone_place_type(zone) == "food":
                    base += 40
                elif zone.function_type == FunctionType.FOOD_HOTSPOT.value:
                    base += 40
            elif key == "school":
                if _zone_place_type(zone) == "school":
                    base += 42
                elif zone.function_type == FunctionType.STUDENT_AREA.value:
                    base += 42
            elif key == "transport":
                if _zone_place_type(zone) == "transport":
                    base += 35
                elif zone.function_type == FunctionType.TRANSPORT_ZONE.value:
                    base += 35
            elif key == "commercial":
                if _zone_place_type(zone) in {"commercial", "busy"}:
                    base += 30
                elif zone.function_type == FunctionType.COMMERCIAL_ZONE.value:
                    base += 30
            elif key == "tourist":
                if _zone_place_type(zone) == "tourist":
                    base += 40
                if _zone_traveler_mix(zone) == "international":
                    base += 18
                if _zone_traveler_mix(zone) == "local":
                    base -= 10
            elif key == "safe_areas":
                if _zone_place_type(zone) == "safety":
                    base -= 45
                elif zone.function_type == FunctionType.SAFETY_CONCERN.value:
                    base -= 45
                else:
                    base += zone.confidence_score * 0.25

            if user_lat is not None and user_lng is not None:
                distance_km = haversine_km(
                    user_lat, user_lng, zone.centroid_lat, zone.centroid_lng
                )
                base -= min(distance_km, 20.0) * 2.0
            return base

        if limit is None:
            return sorted(zones_list, key=score, reverse=True)
        return heapq.nlargest(min(limit, len(zones_list)), zones_list, key=score)

    @classmethod
    def recommend_alternatives(
        cls,
        current_zone: MergedZone,
        zones: Iterable[MergedZone],
        *,
        limit: int = 3,
    ) -> list[MergedZone]:
        candidates: list[tuple[float, MergedZone]] = []
        for zone in zones:
            if zone.zone_id == current_zone.zone_id:
                continue
            distance_km = haversine_km(
                current_zone.centroid_lat,
                current_zone.centroid_lng,
                zone.centroid_lat,
                zone.centroid_lng,
            )
            if distance_km > 6.0:
                continue
            if zone.confidence_score < 35:
                continue

            score = float(zone.priority_score or 0)
            if zone.function_type == current_zone.function_type:
                score += 35
            elif zone.behavior_type == current_zone.behavior_type:
                score += 12
            else:
                continue

            if zone.crowd_level < current_zone.crowd_level:
                score += (current_zone.crowd_level - zone.crowd_level) * 25
            else:
                score -= (zone.crowd_level - current_zone.crowd_level) * 20
            score -= min(distance_km, 6.0) * 2.5
            candidates.append((score, zone))

        candidates.sort(key=lambda pair: pair[0], reverse=True)
        return [zone for _, zone in candidates[:limit]]

"""Thin Redis wrapper with graceful fallback when Redis is unavailable.

Caching is optional. If the Redis client cannot connect (e.g. during tests
or local bootstrapping) the helpers become no-ops so routes still work.
"""
from __future__ import annotations

import json
import logging
from typing import Any

import redis

from app.core.config import settings

log = logging.getLogger(__name__)

_client: redis.Redis | None = None
_disabled: bool = False


def get_client() -> redis.Redis | None:
    global _client, _disabled
    if _disabled:
        return None
    if _client is None:
        try:
            _client = redis.Redis.from_url(settings.redis_url, decode_responses=True)
            _client.ping()
        except Exception as exc:  # pragma: no cover - environmental
            log.warning("Redis unavailable, disabling cache: %s", exc)
            _client = None
            _disabled = True
    return _client


def cache_get(key: str) -> Any | None:
    client = get_client()
    if client is None:
        return None
    try:
        raw = client.get(key)
    except Exception as exc:  # pragma: no cover - environmental
        log.warning("cache_get error for %s: %s", key, exc)
        return None
    if raw is None:
        return None
    try:
        return json.loads(raw)
    except (TypeError, ValueError):
        return None


def cache_set(key: str, value: Any, ttl: int) -> None:
    client = get_client()
    if client is None:
        return
    try:
        client.set(key, json.dumps(value, default=str), ex=ttl)
    except Exception as exc:  # pragma: no cover - environmental
        log.warning("cache_set error for %s: %s", key, exc)


def cache_delete_pattern(pattern: str) -> int:
    """Delete all keys matching `pattern`; returns the number deleted."""
    client = get_client()
    if client is None:
        return 0
    deleted = 0
    try:
        for key in client.scan_iter(match=pattern, count=200):
            client.delete(key)
            deleted += 1
    except Exception as exc:  # pragma: no cover - environmental
        log.warning("cache_delete_pattern error for %s: %s", pattern, exc)
    return deleted


def build_viewport_cache_key(
    min_lat: float,
    min_lng: float,
    max_lat: float,
    max_lng: float,
    *,
    zoom: float | None,
    filter_key: str | None,
    traveler_mix: str | None = None,
    place_type: str | None = None,
) -> str:
    quant = lambda v: round(v, 3)  # noqa: E731
    zoom_part = f"{zoom:.1f}" if zoom is not None else "na"
    filter_part = filter_key or "all"
    mix_part = (traveler_mix or "any").lower()
    place_part = (place_type or "any").lower()
    return (
        "zones:vp:"
        f"{quant(min_lat)}:{quant(min_lng)}:{quant(max_lat)}:{quant(max_lng)}:"
        f"{zoom_part}:{filter_part}:{mix_part}:{place_part}"
    )


def build_zone_feed_cache_key(
    limit: int,
    filter_key: str | None,
    user_lat: float | None,
    user_lng: float | None,
) -> str:
    """Quantized user location (~100 m) so nearby requests share a cache key."""
    quant3 = lambda v: f"{round(v, 3):.3f}"  # noqa: E731
    lat_part = quant3(user_lat) if user_lat is not None else "na"
    lng_part = quant3(user_lng) if user_lng is not None else "na"
    filter_part = (filter_key or "all").lower()
    return f"zones:feed:{limit}:{filter_part}:{lat_part}:{lng_part}"

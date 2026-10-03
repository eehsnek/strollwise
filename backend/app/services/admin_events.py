"""Thread-safe admin event bus for SSE live updates (mobile app → admin console)."""
from __future__ import annotations

import json
import threading
from collections.abc import Callable
from typing import Any

_lock = threading.Lock()
_subscribers: set[Callable[[str], None]] = set()


def subscribe(callback: Callable[[str], None]) -> Callable[[], None]:
    with _lock:
        _subscribers.add(callback)

    def unsubscribe() -> None:
        with _lock:
            _subscribers.discard(callback)

    return unsubscribe


def publish(event_type: str, payload: dict[str, Any] | None = None) -> None:
    message = json.dumps({"type": event_type, **(payload or {})})
    with _lock:
        callbacks = list(_subscribers)
    for callback in callbacks:
        try:
            callback(message)
        except Exception:
            pass


def publish_report_event(action: str, **payload: Any) -> None:
    publish(f"report.{action}", payload)


def publish_zones_updated(**payload: Any) -> None:
    publish("zones.updated", payload)


def publish_dashboard_refresh(**payload: Any) -> None:
    publish("dashboard.refresh", payload)


def publish_catalog_updated(**payload: Any) -> None:
    publish("catalog.updated", payload)

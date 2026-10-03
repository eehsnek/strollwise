from __future__ import annotations

from enum import Enum
from typing import TypeVar

E = TypeVar("E", bound=Enum)


def coerce_enum(value: str | None, enum_cls: type[E], default: E) -> E:
    if value is None:
        return default
    try:
        return enum_cls(value)
    except ValueError:
        return default


def slugify(text: str) -> str:
    return (
        "".join(ch.lower() if ch.isalnum() else "-" for ch in text)
        .strip("-")
        .replace("--", "-")
        .replace("---", "-")
    )

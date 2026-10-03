"""Green–blue behavioral gradient for map zones and cells."""
from __future__ import annotations

LOCAL_RGB = (34, 197, 94)  # #22C55E
INTL_RGB = (59, 130, 246)  # #3B82F6


def local_ratio_from_presence_percent(local_presence_percent: float) -> float:
    return max(0.0, min(1.0, float(local_presence_percent) / 100.0))


def local_ratio_from_counts(local_count: int, international_count: int) -> float:
    total = local_count + international_count
    if total <= 0:
        return 0.5
    return max(0.0, min(1.0, local_count / total))


def local_ratio_from_traveler_mix(
    traveler_mix: str,
    *,
    local_presence_percent: float | None = None,
    local_count: int | None = None,
    international_count: int | None = None,
) -> float:
    if local_count is not None or international_count is not None:
        lc = local_count or 0
        ic = international_count or 0
        if lc + ic > 0:
            return local_ratio_from_counts(lc, ic)
    if local_presence_percent is not None and local_presence_percent > 0:
        return local_ratio_from_presence_percent(local_presence_percent)
    mix = (traveler_mix or "mixed").lower()
    if mix == "local":
        return 1.0
    if mix == "international":
        return 0.0
    return 0.5


def interpolate_rgb(local_ratio: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, float(local_ratio)))
    lr, lg, lb = LOCAL_RGB
    ir, ig, ib = INTL_RGB
    r = round(lr * t + ir * (1.0 - t))
    g = round(lg * t + ig * (1.0 - t))
    b = round(lb * t + ib * (1.0 - t))
    return r, g, b


def map_color_hex(local_ratio: float) -> str:
    r, g, b = interpolate_rgb(local_ratio)
    return f"#{r:02X}{g:02X}{b:02X}"


def fill_color_hex(local_ratio: float, *, alpha_blend: float = 0.72) -> str:
    """Lighter fill for polygon interiors."""
    r, g, b = interpolate_rgb(local_ratio)
    blend = max(0.0, min(1.0, alpha_blend))
    fr = round(255 * (1.0 - blend) + r * blend)
    fg = round(255 * (1.0 - blend) + g * blend)
    fb = round(255 * (1.0 - blend) + b * blend)
    return f"#{fr:02X}{fg:02X}{fb:02X}"

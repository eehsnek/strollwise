#!/usr/bin/env python3
"""Compare catalog zone centers against Mapbox forward geocoding.

Usage (from backend/, with MAPBOX_ACCESS_TOKEN in .env):

    python scripts/verify_zone_placements_mapbox.py
    python scripts/verify_zone_placements_mapbox.py --max-km 0.8
"""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.services.mapbox_geocoding_service import MapboxGeocodingService
from app.services.zone_catalog import CEBU_ZONE_CATALOG


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify zone catalog centers via Mapbox")
    parser.add_argument(
        "--max-km",
        type=float,
        default=1.0,
        help="Fail if geocoded point is farther than this from catalog center",
    )
    args = parser.parse_args()

    service = MapboxGeocodingService()
    if not service.enabled:
        print("MAPBOX_ACCESS_TOKEN is not set — add it to backend/.env", file=sys.stderr)
        return 1

    failed = 0
    print(f"{'Zone':<32} {'km':>6}  {'Mapbox place'}")
    print("-" * 72)

    for entry in CEBU_ZONE_CATALOG:
        query = f"{entry.zone_name}, Cebu, Philippines"
        hits = service.forward(query, limit=1)
        if not hits:
            print(f"{entry.zone_name:<32} {'—':>6}  (no geocode hit)")
            failed += 1
            continue
        hit = hits[0]
        km = haversine_km(
            entry.center_lat,
            entry.center_lng,
            hit.lat,
            hit.lng,
        )
        ok = km <= args.max_km
        status = "ok" if ok else "FAIL"
        print(
            f"{entry.zone_name:<32} {km:6.2f}  {hit.place_name[:40]}  [{status}]"
        )
        if not ok:
            failed += 1

    print("-" * 72)
    if failed:
        print(f"{failed} zone(s) outside {args.max_km} km threshold")
        return 1
    print("All zones within threshold")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

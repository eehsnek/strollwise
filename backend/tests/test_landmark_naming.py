from __future__ import annotations

from app.services.landmark_service import (
    CEBU_LANDMARKS,
    landmark_for_centroid,
    nearest_landmark,
)
from app.services.zone_merge_service import ZoneMergeService


def test_nearest_landmark_picks_it_park_when_near_it_park():
    name, distance_km = landmark_for_centroid(10.3306, 123.9056)
    assert name == "IT Park"
    assert distance_km < 0.05


def test_nearest_landmark_picks_colon_when_near_downtown():
    # Slightly off Colon Street, still closest to Colon.
    name, _ = landmark_for_centroid(10.2968, 123.9022)
    assert name == "Colon Street"


def test_nearest_landmark_always_returns_one_entry():
    # Far-away coordinate still resolves to the closest Cebu landmark.
    far = nearest_landmark(0.0, 0.0)
    assert far in CEBU_LANDMARKS


def test_compose_display_name_uses_function_plus_landmark():
    name = ZoneMergeService._compose_display_name("Tourist", "Food Hotspot", "Colon Street")
    assert name == "Food Hotspot near Colon Street"


def test_compose_display_name_falls_back_to_prefix_when_generic():
    name = ZoneMergeService._compose_display_name("Mixed", "Area", "Ayala Center")
    assert name == "Mixed Area near Ayala Center"

    emerging = ZoneMergeService._compose_display_name("Local", "Emerging Zone", "Lahug")
    assert emerging == "Local Area near Lahug"

"""Tests for curated zone place recommendations."""
from app.services.place_recommendations_service import fetch_place_recommendations


def test_lahug_food_returns_at_least_three():
    picks = fetch_place_recommendations(
        lat=10.3335,
        lng=123.9030,
        vibe="food",
        area_label="Lahug",
        limit=8,
    )
    assert len(picks) >= 3
    assert any("JY Square" in p.name or "Anzani" in p.name for p in picks)


def test_all_zone_labels_resolve():
    zones = [
        ("Talamban", 10.3694, 123.9185),
        ("Pardo", 10.2811, 123.8456),
        ("Minglanilla Proper", 10.2446, 123.7963),
        ("Talisay Residential Area", 10.2449, 123.8493),
        ("Mactan Resort Zone", 10.2998, 124.0112),
        ("Colon Basilica Heritage Zone", 10.2942, 123.9017),
        ("IT Park Business Zone", 10.3295, 123.9067),
        ("SRP Tourism Belt", 10.2869, 123.8808),
        ("Ayala Center Cebu", 10.3174, 123.9058),
        ("Fuente Osmeña", 10.3100, 123.8916),
        ("SM City Cebu", 10.3116, 123.9182),
        ("Carbon Market Area", 10.2933, 123.8998),
        ("Lahug", 10.3335, 123.9030),
        ("Escario", 10.3157, 123.8919),
    ]
    for label, lat, lng in zones:
        picks = fetch_place_recommendations(
            lat=lat,
            lng=lng,
            vibe="food",
            area_label=label,
            limit=8,
        )
        assert len(picks) >= 3, f"Expected 3+ food picks for {label}"


def test_vibes_return_distinct_names():
    lahug_lat, lahug_lng = 10.3335, 123.9030
    food = {
        p.name
        for p in fetch_place_recommendations(
            lat=lahug_lat,
            lng=lahug_lng,
            vibe="food",
            area_label="Lahug",
        )
    }
    tourist = {
        p.name
        for p in fetch_place_recommendations(
            lat=lahug_lat,
            lng=lahug_lng,
            vibe="tourist",
            area_label="Lahug",
        )
    }
    assert food != tourist

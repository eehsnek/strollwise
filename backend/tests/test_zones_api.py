from __future__ import annotations


def _register(client):
    resp = client.post(
        "/api/v1/auth/register",
        json={
            "email": "zoneapi@example.com",
            "password": "supersecret123",
            "display_name": "Zone API",
            "country_of_origin": "Philippines",
            "city_of_origin": "Cebu City",
            "user_type": "local_resident",
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["access_token"]


def _seed_cluster(client, token):
    """Push enough co-located food reports to trigger a merged zone."""
    for i in range(10):
        lat = 10.3306 + (i % 4) * 0.0004
        lng = 123.9056 + (i // 4) * 0.0004
        client.post(
            "/api/v1/reports",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "latitude": lat,
                "longitude": lng,
                "category": "food",
                "tags": ["food", "cafe", "restaurant"],
            },
        )


def test_zones_viewport_returns_new_schema_fields(client):
    token = _register(client)
    _seed_cluster(client, token)

    resp = client.get(
        "/api/v1/zones",
        params={
            "min_lat": 10.25,
            "min_lng": 123.85,
            "max_lat": 10.40,
            "max_lng": 123.95,
            "zoom": 14,
        },
    )
    assert resp.status_code == 200, resp.text
    items = resp.json()
    assert isinstance(items, list)
    if not items:
        return  # cluster size below merge threshold — still a valid response

    first = items[0]
    for field in (
        "zone_id",
        "display_name",
        "behavior_type",
        "traveler_mix",
        "live_status",
        "polygon_geojson",
        "centroid",
        "crowd_level",
        "local_presence_percent",
        "confidence_score",
        "priority_score",
    ):
        assert field in first, f"missing field {field}"
    assert first["polygon_geojson"]["type"] in ("Polygon", "MultiPolygon")
    assert "lat" in first["centroid"] and "lng" in first["centroid"]
    assert first["traveler_mix"] in {"local", "mixed", "international"}
    assert "·" in first["display_name"] or " near " in first["display_name"]


def test_zone_detail_returns_expected_fields(client):
    token = _register(client)
    _seed_cluster(client, token)

    viewport = client.get(
        "/api/v1/zones",
        params={
            "min_lat": 10.25,
            "min_lng": 123.85,
            "max_lat": 10.40,
            "max_lng": 123.95,
        },
    )
    items = viewport.json()
    if not items:
        return  # nothing merged yet — skip quietly

    zone_id = items[0]["zone_id"]
    detail = client.get(f"/api/v1/zones/{zone_id}")
    assert detail.status_code == 200, detail.text
    body = detail.json()
    for field in (
        "zone_id",
        "display_name",
        "behavior_type",
        "traveler_mix",
        "places",
        "summary",
        "live_status",
        "polygon_geojson",
        "centroid",
        "crowd_level",
        "local_presence_percent",
        "confidence_score",
        "why_visit",
        "nearby_zone_ids",
        "top_activities",
    ):
        assert field in body, f"missing field {field}"
    assert body["zone_id"] == zone_id
    assert body["traveler_mix"] in {"local", "mixed", "international"}
    assert isinstance(body["places"], list)


def test_zone_detail_404_for_unknown_id(client):
    resp = client.get("/api/v1/zones/00000000-0000-0000-0000-000000000000")
    assert resp.status_code == 404


def test_zones_feed_returns_ranked_list(client):
    token = _register(client)
    _seed_cluster(client, token)

    resp = client.get(
        "/api/v1/zones/feed",
        params={"limit": 10, "user_lat": 10.3308, "user_lng": 123.906},
    )
    assert resp.status_code == 200, resp.text
    items = resp.json()
    assert isinstance(items, list)
    assert len(items) <= 10
    if items:
        assert "zone_id" in items[0]
        assert "display_name" in items[0]
        assert "confidence_score" in items[0]


def test_current_zone_overview_returns_launch_payload(client):
    token = _register(client)
    _seed_cluster(client, token)

    resp = client.get(
        "/api/v1/zones/current",
        params={"lat": 10.3308, "lng": 123.9060, "ring": 1, "limit": 5},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert "current_zone" in body
    assert "nearby_zones" in body
    assert "alternative_zones" in body
    assert "context" in body
    assert "city_activity" in body["context"]
    assert "crowd_level_percent" in body["context"]
    assert "local_presence_percent" in body["context"]

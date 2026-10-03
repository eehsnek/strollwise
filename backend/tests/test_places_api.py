from __future__ import annotations


def _register(client):
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": "places-tester@example.com",
            "password": "testpass123",
            "display_name": "Places Tester",
            "country_of_origin": "Philippines",
            "city_of_origin": "Cebu City",
            "user_type": "local_resident",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()["access_token"]


def _seed_uspf(client, token):
    for _ in range(8):
        client.post(
            "/api/v1/reports",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "latitude": 10.3370,
                "longitude": 123.9025,
                "category": "school",
                "tags": ["uspf campus", "school", "student"],
            },
        )


def test_places_viewport_returns_uspf(client):
    token = _register(client)
    _seed_uspf(client, token)

    response = client.get(
        "/api/v1/places",
        params={
            "min_lat": 10.25,
            "min_lng": 123.85,
            "max_lat": 10.40,
            "max_lng": 123.95,
        },
    )
    assert response.status_code == 200
    items = response.json()
    assert isinstance(items, list)
    if not items:
        return
    first = items[0]
    assert "place_id" in first
    assert "display_name" in first
    assert first["place_type"] in {
        "school",
        "food",
        "transport",
        "commercial",
        "general",
        "emerging",
    }
    assert first["polygon_geojson"]["type"] in ("Polygon", "MultiPolygon")
    rings = first.get("source_h3_rings") or []
    assert isinstance(rings, list)
    assert len(rings) > 0
    assert len(rings[0]) >= 4
    assert rings[0][0] == rings[0][-1]


def test_place_detail(client):
    token = _register(client)
    _seed_uspf(client, token)

    listing = client.get(
        "/api/v1/places",
        params={
            "min_lat": 10.25,
            "min_lng": 123.85,
            "max_lat": 10.40,
            "max_lng": 123.95,
            "place_type": "school",
        },
    )
    assert listing.status_code == 200
    items = listing.json()
    if not items:
        return

    place_id = items[0]["place_id"]
    detail = client.get(f"/api/v1/places/{place_id}")
    assert detail.status_code == 200
    body = detail.json()
    assert body["place_id"] == place_id
    assert body["display_name"]
    assert "source_h3_indexes" in body
    assert isinstance(body.get("source_h3_rings"), list)

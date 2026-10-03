from __future__ import annotations


def _register(client, email: str = "report@example.com"):
    resp = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "supersecret123",
            "display_name": "Reporter",
            "country_of_origin": "Philippines",
            "city_of_origin": "Cebu City",
            "user_type": "local_resident",
        },
    )
    assert resp.status_code == 201
    return resp.json()["access_token"]


def _post_food_report(client, token: str, note: str) -> dict:
    resp = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "latitude": 10.3157,
            "longitude": 123.8854,
            "category": "food",
            "tags": ["food", "cafe"],
            "note_text": note,
        },
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


def test_create_report_converts_latlng_into_h3(client):
    token_a = _register(client, "reporter-a@example.com")
    first = _post_food_report(client, token_a, "Great spot")
    assert first["h3_index"]
    assert first["resolution"] == 8
    assert first["category"] == "food"
    assert first["aggregation"]["matching_count"] == 1
    assert first["aggregation"]["threshold"] == 3
    assert first["aggregation"]["threshold_met"] is False
    assert first["aggregation"]["remaining_to_threshold"] == 2

    token_b = _register(client, "reporter-b@example.com")
    second = _post_food_report(client, token_b, "Second person")
    assert second["aggregation"]["matching_count"] == 2
    assert second["aggregation"]["threshold_met"] is False
    assert second["aggregation"]["remaining_to_threshold"] == 1

    token_c = _register(client, "reporter-c@example.com")
    third = _post_food_report(client, token_c, "Third person forms cell")
    assert third["aggregation"]["matching_count"] == 3
    assert third["aggregation"]["threshold_met"] is True
    assert third["aggregation"]["remaining_to_threshold"] == 0


def test_single_user_cannot_form_cell_with_multiple_reports(client):
    """One tag per cell per user; extra submits are rejected before aggregation."""
    token = _register(client, "solo@example.com")
    body = _post_food_report(client, token, "Solo report")
    assert body["aggregation"]["matching_count"] == 1
    assert body["aggregation"]["threshold_met"] is False
    assert body["aggregation"]["remaining_to_threshold"] == 2

    dup = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "latitude": 10.3157,
            "longitude": 123.8854,
            "category": "food",
            "tags": ["food", "cafe"],
            "note_text": "Duplicate attempt",
        },
    )
    assert dup.status_code == 422
    assert "pending tag" in dup.json()["detail"].lower()


def test_zones_endpoint_returns_list(client):
    # Three distinct people in the same H3 cell trigger approval/publication.
    for email in (
        "zones-a@example.com",
        "zones-b@example.com",
        "zones-c@example.com",
    ):
        token = _register(client, email)
        _post_food_report(client, token, f"Report from {email}")
    resp = client.get(
        "/api/v1/zones",
        params={
            "min_lat": 10.2,
            "min_lng": 123.8,
            "max_lat": 10.4,
            "max_lng": 124.0,
            "zoom": 14,
        },
    )
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)


def test_report_rejects_unknown_category(client):
    token = _register(client)
    resp = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "latitude": 10.3157,
            "longitude": 123.8854,
            "category": "teleportation",
            "tags": [],
        },
    )
    assert resp.status_code == 422


def test_rejects_duplicate_pending_in_same_cell(client):
    token = _register(client, "dup-pending@example.com")
    first = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "latitude": 10.3157,
            "longitude": 123.8854,
            "category": "food",
            "tags": ["food"],
        },
    )
    assert first.status_code == 201
    second = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "latitude": 10.3157,
            "longitude": 123.8854,
            "category": "food",
            "tags": ["cafe"],
        },
    )
    assert second.status_code == 422
    assert "pending tag" in second.json()["detail"].lower()


def test_rejects_per_cell_cooldown_after_visible_report(
    client, db_session, monkeypatch
):
    from datetime import datetime, timedelta, timezone

    from sqlalchemy import desc, select

    from app.core.config import get_settings
    from app.models.report import Report

    monkeypatch.setenv("REPORT_COOLDOWN_HOURS_PER_CELL", "24")
    get_settings.cache_clear()

    token = _register(client, "cooldown@example.com")
    lat, lng = 10.3188, 123.8888
    first = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "latitude": lat,
            "longitude": lng,
            "category": "food",
            "tags": ["cooldown_test"],
        },
    )
    assert first.status_code == 201
    h3_index = first.json()["h3_index"]

    stmt = (
        select(Report)
        .where(Report.h3_index == h3_index)
        .order_by(desc(Report.created_at))
        .limit(1)
    )
    report = db_session.execute(stmt).scalars().first()
    assert report is not None
    report.visibility_status = "visible"
    report.created_at = datetime.now(timezone.utc) - timedelta(hours=1)
    db_session.commit()

    second = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "latitude": lat,
            "longitude": lng,
            "category": "food",
            "tags": ["cooldown_retry"],
        },
    )
    assert second.status_code == 422
    assert "recently" in second.json()["detail"].lower()


def test_rejects_hourly_rate_limit(client, monkeypatch):
    from app.core.config import get_settings
    from app.services import h3_service

    monkeypatch.setenv("REPORT_MAX_PER_USER_PER_HOUR", "2")
    monkeypatch.setenv("REPORT_COOLDOWN_HOURS_PER_CELL", "0")
    get_settings.cache_clear()

    token = _register(client, "ratelimit@example.com")
    cfg = get_settings()
    seen_cells: set[str] = set()
    locations: list[tuple[float, float]] = []
    lat, lng = 10.3157, 123.8854
    while len(locations) < 3:
        cell = h3_service.latlng_to_cell(lat, lng, cfg.h3_resolution)
        if cell not in seen_cells:
            seen_cells.add(cell)
            locations.append((lat, lng))
        lat += 0.012
        lng += 0.012

    for lat, lng in locations[:2]:
        resp = client.post(
            "/api/v1/reports",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "latitude": lat,
                "longitude": lng,
                "category": "food",
                "tags": ["rate_limit_probe"],
            },
        )
        assert resp.status_code == 201, resp.text

    lat, lng = locations[2]
    blocked = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "latitude": lat,
            "longitude": lng,
            "category": "food",
            "tags": ["rate_limit_probe"],
        },
    )
    assert blocked.status_code == 422
    assert "last hour" in blocked.json()["detail"].lower()


def test_report_rejects_sensitive_area(client):
    token = _register(client)
    resp = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "latitude": 10.2968,
            "longitude": 123.8946,
            "category": "food",
            "tags": ["canteen"],
        },
    )
    assert resp.status_code == 422
    assert "sensitive" in resp.json()["detail"]


def test_report_feed_only_includes_approved_reports(client):
    token = _register(client)
    first = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "latitude": 10.3201,
            "longitude": 123.9021,
            "category": "transport",
            "tags": ["traffic"],
        },
    )
    assert first.status_code == 201
    feed = client.get("/api/v1/reports/feed")
    assert feed.status_code == 200
    assert feed.json() == []


def test_uspf_tag_triggers_single_report_approval(client):
    token = _register(client)
    lat, lng = 10.3380, 123.9010
    resp = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "latitude": lat,
            "longitude": lng,
            "category": "school",
            "tags": ["uspf campus", "school", "public", "exact_road_spot"],
        },
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["aggregation"]["threshold_met"] is True


def test_place_markers_returns_uspf_pins(client):
    token = _register(client)
    lat, lng = 10.3380, 123.9010
    assert (
        client.post(
            "/api/v1/reports",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "latitude": lat,
                "longitude": lng,
                "category": "school",
                "tags": ["uspf campus", "school", "public", "exact_road_spot"],
            },
        ).status_code
        == 201
    )
    mr = client.get(
        "/api/v1/reports/place-markers",
        params={
            "min_lat": 10.32,
            "max_lat": 10.36,
            "min_lng": 123.88,
            "max_lng": 123.92,
            "tag": "uspf",
        },
    )
    assert mr.status_code == 200
    markers = mr.json()
    assert len(markers) >= 1
    assert markers[0]["validated"] is True
    assert abs(markers[0]["latitude"] - lat) < 0.01
    assert abs(markers[0]["longitude"] - lng) < 0.01


def test_my_pending_pins_lists_only_own_pending(client):
    token = _register(client)
    lat, lng = 10.3215, 123.9012
    assert (
        client.post(
            "/api/v1/reports",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "latitude": lat,
                "longitude": lng,
                "category": "food",
                "tags": ["pending_map_test"],
            },
        ).status_code
        == 201
    )
    res = client.get(
        "/api/v1/reports/my-pending-pins",
        headers={"Authorization": f"Bearer {token}"},
        params={
            "min_lat": 10.31,
            "max_lat": 10.33,
            "min_lng": 123.89,
            "max_lng": 123.91,
        },
    )
    assert res.status_code == 200
    pins = res.json()
    assert len(pins) >= 1
    assert all(p["validated"] is False for p in pins)
    assert any(abs(float(p["latitude"]) - lat) < 0.02 for p in pins)


def test_me_contributions_reflects_submitted_reports(client):
    import uuid

    email = f"contrib_{uuid.uuid4().hex[:10]}@example.com"
    reg = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": "supersecret123",
            "display_name": "Contrib",
            "country_of_origin": "Philippines",
            "city_of_origin": "Cebu City",
            "user_type": "local_resident",
        },
    )
    assert reg.status_code == 201, reg.text
    token = reg.json()["access_token"]
    empty = client.get(
        "/api/v1/users/me/contributions",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert empty.status_code == 200
    assert empty.json()["stats"]["submitted"] == 0

    assert (
        client.post(
            "/api/v1/reports",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "latitude": 10.3157,
                "longitude": 123.8854,
                "category": "food",
                "tags": ["food", "cafe"],
            },
        ).status_code
        == 201
    )
    filled = client.get(
        "/api/v1/users/me/contributions",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert filled.status_code == 200
    body = filled.json()
    assert body["stats"]["submitted"] >= 1
    assert body["recent_reports"]
    assert body["contributor_label"]
    assert body["recent_reports"][0]["category"] == "food"

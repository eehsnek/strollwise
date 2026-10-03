from __future__ import annotations

from uuid import UUID

import pytest

from app.core.security import hash_password
from app.models.enums import VisibilityStatus
from app.models.report import Report
from app.models.user import User
from app.utils.user_type_utils import apply_user_type_to_user


def _register(client, email: str, **overrides):
    body = {
        "email": email,
        "password": "supersecret123",
        "display_name": "Test User",
        "country_of_origin": "Philippines",
        "city_of_origin": "Cebu City",
        "user_type": "local_resident",
        "accepted_research_consent": True,
    }
    body.update(overrides)
    return client.post("/api/v1/auth/register", json=body)


def _make_admin(db_session, email: str = "admin@test.com") -> User:
    from app.repositories.user_repository import UserRepository

    existing = UserRepository(db_session).get_by_email(email)
    if existing is not None:
        existing.is_admin = True
        db_session.commit()
        db_session.refresh(existing)
        return existing
    user = User(
        email=email,
        password_hash=hash_password("supersecret123"),
        display_name="Admin",
        traveler_type="local",
        user_type="local_resident",
        is_admin=True,
        accepted_research_consent=True,
    )
    apply_user_type_to_user(user)
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    return user


def _admin_headers(client, db_session, email: str = "admin@test.com") -> dict[str, str]:
    _make_admin(db_session, email)
    login = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": "supersecret123"},
    )
    token = login.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _user_headers(client, email: str = "user@test.com") -> dict[str, str]:
    _register(client, email)
    login = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": "supersecret123"},
    )
    token = login.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def _pending_report(db_session, user_id: UUID, h3_index: str = "8828308281fffff") -> Report:
    report = Report(
        user_id=user_id,
        h3_index=h3_index,
        resolution=8,
        latitude_raw=10.31,
        longitude_raw=123.89,
        category="food",
        tags_json=["good food"],
        visibility_status=VisibilityStatus.PENDING.value,
    )
    db_session.add(report)
    db_session.commit()
    db_session.refresh(report)
    return report


def test_non_admin_forbidden(client, db_session):
    headers = _user_headers(client)
    resp = client.get("/api/v1/admin/moderation/reports", headers=headers)
    assert resp.status_code == 403


def test_admin_lists_pending_reports(client, db_session):
    admin = _make_admin(db_session)
    _pending_report(db_session, admin.id)
    headers = _admin_headers(client, db_session, admin.email)
    resp = client.get("/api/v1/admin/moderation/reports", headers=headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["total"] >= 1
    item = data["items"][0]
    assert "h3_index" in item
    assert "latitude_raw" not in item
    assert "user_id" not in item


def test_admin_approve_creates_audit_log(client, db_session):
    admin = _make_admin(db_session, "admin-approve@test.com")
    report = _pending_report(db_session, admin.id)
    headers = _admin_headers(client, db_session, admin.email)
    resp = client.post(
        f"/api/v1/admin/moderation/reports/{report.id}/approve",
        headers=headers,
    )
    assert resp.status_code == 200
    assert resp.json()["report"]["visibility_status"] == "visible"

    audit = client.get("/api/v1/admin/audit", headers=headers)
    assert audit.status_code == 200
    actions = [e["action_type"] for e in audit.json()["items"]]
    assert "report.admin_approve" in actions


def test_admin_reject_and_flag(client, db_session):
    admin = _make_admin(db_session, "admin-flag@test.com")
    report = _pending_report(db_session, admin.id, h3_index="8828308283fffff")
    headers = _admin_headers(client, db_session, admin.email)

    reject = client.post(
        f"/api/v1/admin/moderation/reports/{report.id}/reject",
        headers=headers,
    )
    assert reject.status_code == 200
    assert reject.json()["report"]["visibility_status"] == "removed"

    report2 = _pending_report(db_session, admin.id, h3_index="8828308285fffff")
    flag = client.post(
        f"/api/v1/admin/moderation/reports/{report2.id}/flag",
        headers=headers,
    )
    assert flag.status_code == 200
    assert flag.json()["report"]["visibility_status"] == "flagged"


def test_admin_config_get_and_patch(client, db_session):
    headers = _admin_headers(client, db_session)
    get_resp = client.get("/api/v1/admin/config", headers=headers)
    assert get_resp.status_code == 200
    assert get_resp.json()["pending_min_reports_per_cell"] == 3

    patch = client.patch(
        "/api/v1/admin/config",
        headers=headers,
        json={"pending_min_reports_per_cell": 4},
    )
    assert patch.status_code == 200
    assert patch.json()["pending_min_reports_per_cell"] == 4


def test_admin_export_reports_anonymized(client, db_session):
    admin = _make_admin(db_session)
    _pending_report(db_session, admin.id)
    headers = _admin_headers(client, db_session)
    resp = client.get("/api/v1/admin/analytics/export/reports?fmt=json", headers=headers)
    assert resp.status_code == 200
    body = resp.text
    assert "latitude" not in body
    assert "email" not in body


def test_admin_dashboard_stats(client, db_session):
    headers = _admin_headers(client, db_session)
    resp = client.get("/api/v1/admin/dashboard/stats", headers=headers)
    assert resp.status_code == 200
    assert "pending_reports" in resp.json()


def test_admin_users_list(client, db_session):
    admin = _make_admin(db_session, "admin-users@test.com")
    headers = _admin_headers(client, db_session, admin.email)
    resp = client.get("/api/v1/admin/users", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["total"] >= 1


def test_admin_catalog_list(client, db_session):
    headers = _admin_headers(client, db_session)
    resp = client.get("/api/v1/admin/catalog/zones", headers=headers)
    assert resp.status_code == 200
    entries = resp.json()
    assert len(entries) >= 1
    assert "zone_name" in entries[0]

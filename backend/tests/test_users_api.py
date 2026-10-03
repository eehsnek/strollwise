from __future__ import annotations


def test_users_me_patch_manual_map_round_trip(client):
    reg = client.post(
        "/api/v1/auth/register",
        json={
            "email": "mapper@example.com",
            "password": "supersecret123",
            "display_name": "Mapper",
            "country_of_origin": "Philippines",
            "city_of_origin": "Cebu City",
            "user_type": "local_resident",
        },
    )
    assert reg.status_code == 201, reg.text
    token = reg.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    patch = client.patch(
        "/api/v1/users/me",
        headers=headers,
        json={"manual_map_lat": 10.3173, "manual_map_lng": 123.9058},
    )
    assert patch.status_code == 200, patch.text
    body = patch.json()
    assert body["manual_map_lat"] == 10.3173
    assert body["manual_map_lng"] == 123.9058

    me = client.get("/api/v1/users/me", headers=headers)
    assert me.status_code == 200
    again = me.json()
    assert again["manual_map_lat"] == 10.3173
    assert again["manual_map_lng"] == 123.9058

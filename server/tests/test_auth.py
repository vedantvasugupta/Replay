from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_signup_login_refresh(async_client) -> None:
    signup_payload = {"email": "test@example.com", "password": "strongpass1"}
    resp = await async_client.post("/auth/signup", json=signup_payload)
    assert resp.status_code == 201
    data = resp.json()
    assert data["email"] == signup_payload["email"]

    login_resp = await async_client.post("/auth/login", json=signup_payload)
    assert login_resp.status_code == 200
    tokens = login_resp.json()
    assert tokens["access_token"]
    assert tokens["refresh_token"]

    refresh_resp = await async_client.post("/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert refresh_resp.status_code == 200
    refreshed = refresh_resp.json()
    assert refreshed["access_token"]

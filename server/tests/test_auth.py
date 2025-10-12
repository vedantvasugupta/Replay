import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_signup_and_login(client: AsyncClient):
    signup_resp = await client.post("/auth/signup", json={"email": "user@example.com", "password": "password123"})
    assert signup_resp.status_code == 201

    login_resp = await client.post("/auth/login", json={"email": "user@example.com", "password": "password123"})
    assert login_resp.status_code == 200
    tokens = login_resp.json()
    assert "access" in tokens and "refresh" in tokens

    refresh_resp = await client.post("/auth/refresh", json={"refresh": tokens["refresh"]})
    assert refresh_resp.status_code == 200

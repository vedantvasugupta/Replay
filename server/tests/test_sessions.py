from __future__ import annotations

import asyncio
from io import BytesIO

import pytest


async def _auth_headers(async_client) -> dict[str, str]:
    payload = {"email": "flow@example.com", "password": "strongpass1"}
    await async_client.post("/auth/signup", json=payload)
    login = await async_client.post("/auth/login", json=payload)
    tokens = login.json()
    return {"Authorization": f"Bearer {tokens['access_token']}"}


@pytest.mark.asyncio
async def test_full_session_flow(async_client) -> None:
    headers = await _auth_headers(async_client)

    upload_url_resp = await async_client.post(
        "/upload-url",
        json={"filename": "meeting.m4a", "mime": "audio/m4a"},
        headers=headers,
    )
    assert upload_url_resp.status_code == 200
    asset_payload = upload_url_resp.json()
    asset_id = asset_payload["assetId"]

    audio_buffer = BytesIO(b"fake audio data")
    files = {"file": ("meeting.m4a", audio_buffer.getvalue(), "audio/m4a")}
    data = {"assetId": str(asset_id)}
    upload_resp = await async_client.post("/upload", data=data, files=files, headers=headers)
    assert upload_resp.status_code == 200

    ingest_resp = await async_client.post(
        "/ingest",
        json={"assetId": asset_id, "durationSec": 5},
        headers=headers,
    )
    assert ingest_resp.status_code == 200
    session_id = ingest_resp.json()["sessionId"]

    # Wait for background worker to process
    await asyncio.sleep(0.1)

    sessions_resp = await async_client.get("/sessions", headers=headers)
    assert sessions_resp.status_code == 200
    sessions = sessions_resp.json()
    assert sessions[0]["status"] in {"processing", "ready"}

    # Poll until ready
    for _ in range(10):
        detail_resp = await async_client.get(f"/session/{session_id}", headers=headers)
        assert detail_resp.status_code == 200
        detail = detail_resp.json()
        if detail["meta"]["status"] == "ready":
            break
        await asyncio.sleep(0.1)
    else:
        pytest.fail("Session did not become ready in time")

    chat_resp = await async_client.post(
        f"/session/{session_id}/chat",
        json={"message": "What happened?"},
        headers=headers,
    )
    assert chat_resp.status_code == 200
    chat_data = chat_resp.json()
    assert "assistantMessage" in chat_data

import io

import pytest
from httpx import AsyncClient

from src.services.jobs import jobs_service


@pytest.mark.asyncio
async def test_session_flow(client: AsyncClient):
    await client.post("/auth/signup", json={"email": "flow@example.com", "password": "password123"})
    login_resp = await client.post("/auth/login", json={"email": "flow@example.com", "password": "password123"})
    tokens = login_resp.json()
    headers = {"Authorization": f"Bearer {tokens['access']}"}

    upload_url_resp = await client.post(
        "/upload-url",
        json={"filename": "test.m4a", "mime": "audio/m4a"},
        headers=headers,
    )
    data = upload_url_resp.json()
    asset_id = data["assetId"]

    audio_bytes = io.BytesIO(b"fake audio data")
    files = {"file": ("test.m4a", audio_bytes, "audio/m4a"), "assetId": (None, asset_id)}
    upload_resp = await client.post("/upload", files=files, headers=headers)
    assert upload_resp.status_code == 200

    ingest_resp = await client.post("/ingest", json={"assetId": asset_id}, headers=headers)
    assert ingest_resp.status_code == 200

    await jobs_service.queue.join()

    sessions_resp = await client.get("/sessions", headers=headers)
    assert sessions_resp.status_code == 200
    sessions = sessions_resp.json()
    assert len(sessions) == 1
    session_id = sessions[0]["id"]

    detail_resp = await client.get(f"/session/{session_id}", headers=headers)
    assert detail_resp.status_code == 200
    detail = detail_resp.json()
    assert detail["meta"]["status"] in ("ready", "processing")

    chat_resp = await client.post(
        f"/session/{session_id}/chat",
        json={"message": "What happened?"},
        headers=headers,
    )
    assert chat_resp.status_code == 200

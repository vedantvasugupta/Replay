from __future__ import annotations

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.deps import get_current_user, get_db_session
from ..models.audio_asset import AudioAsset
from ..models.user import User
from ..schemas.upload import UploadIngestRequest, UploadUrlRequest, UploadUrlResponse
from ..services.jobs_service import JobsService
from ..services.session_service import SessionService
from ..services.storage_service import StorageService


def get_storage_service() -> StorageService:
    from ..app import get_app_state

    return get_app_state().storage_service


def get_jobs_service() -> JobsService:
    from ..app import get_app_state

    return get_app_state().jobs_service


def get_session_service() -> SessionService:
    from ..app import get_app_state

    return get_app_state().session_service


router = APIRouter(tags=["uploads"])


@router.post("/upload-url", response_model=UploadUrlResponse)
async def request_upload_url(
    payload: UploadUrlRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db_session),
    storage: StorageService = Depends(get_storage_service),
) -> UploadUrlResponse:
    asset = await storage.create_asset(db, user, payload.filename, payload.mime)
    return UploadUrlResponse(upload_url="/upload", asset_id=asset.id)


@router.post("/upload")
async def upload_file(
    asset_id: int = Form(..., alias="assetId"),
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db_session),
    storage: StorageService = Depends(get_storage_service),
):
    asset = await db.get(AudioAsset, asset_id)
    if not asset or asset.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Asset not found")

    saved_size = await storage.save_upload(asset, file)
    await storage.update_asset_size(db, asset, saved_size)
    return {"assetId": asset.id}


@router.post("/ingest")
async def ingest_recording(
    payload: UploadIngestRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db_session),
    storage: StorageService = Depends(get_storage_service),
    session_service: SessionService = Depends(get_session_service),
    jobs: JobsService = Depends(get_jobs_service),
):
    asset = await db.get(AudioAsset, payload.asset_id)
    if not asset or asset.user_id != user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Asset not found")

    if asset.size == 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Asset not uploaded yet")

    session_obj = await session_service.create_session(db, user.id, asset, payload.duration_sec, payload.title)
    await jobs.enqueue_transcription(db, session_obj)
    return {"sessionId": session_obj.id, "status": session_obj.status.value}

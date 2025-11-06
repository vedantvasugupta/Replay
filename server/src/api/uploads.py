from __future__ import annotations

import logging

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

logger = logging.getLogger(__name__)


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
    logger.info(f"[upload-url] User {user.id} requesting upload URL for {payload.filename} ({payload.mime})")
    asset = await storage.create_asset(db, user, payload.filename, payload.mime)
    logger.info(f"[upload-url] Created asset {asset.id} at path: {asset.path}")
    return UploadUrlResponse(upload_url="/upload", asset_id=asset.id)


@router.post("/upload")
async def upload_file(
    asset_id: int = Form(..., alias="assetId"),
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db_session),
    storage: StorageService = Depends(get_storage_service),
):
    logger.info(f"[upload] User {user.id} uploading file for asset {asset_id}")
    logger.info(f"[upload] File details - filename: {file.filename}, content_type: {file.content_type}, size: {file.size if hasattr(file, 'size') else 'unknown'}")

    asset = await db.get(AudioAsset, asset_id)
    if not asset or asset.user_id != user.id:
        logger.warning(f"[upload] Asset {asset_id} not found or unauthorized for user {user.id}")
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Asset not found")

    logger.info(f"[upload] Asset {asset_id} found, saving to path: {asset.path}")

    try:
        saved_size = await storage.save_upload(asset, file)
        logger.info(f"[upload] Successfully saved {saved_size} bytes to disk for asset {asset_id}")

        await storage.update_asset_size(db, asset, saved_size)
        logger.info(f"[upload] Updated asset {asset_id} size in DB to {saved_size} bytes")

        return {"assetId": asset.id}
    except Exception as e:
        logger.error(f"[upload] Failed to upload file for asset {asset_id}: {e}", exc_info=True)
        raise


@router.post("/ingest")
async def ingest_recording(
    payload: UploadIngestRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db_session),
    storage: StorageService = Depends(get_storage_service),
    session_service: SessionService = Depends(get_session_service),
    jobs: JobsService = Depends(get_jobs_service),
):
    logger.info(f"[ingest] User {user.id} requesting ingest for asset {payload.asset_id}")

    asset = await db.get(AudioAsset, payload.asset_id)
    if not asset or asset.user_id != user.id:
        logger.warning(f"[ingest] Asset {payload.asset_id} not found or unauthorized for user {user.id}")
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Asset not found")

    logger.info(f"[ingest] Asset {payload.asset_id} has size: {asset.size} bytes")

    if asset.size == 0:
        logger.error(f"[ingest] Asset {payload.asset_id} has 0 bytes - upload not completed")
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Asset not uploaded yet")

    session_obj = await session_service.create_session(db, user.id, asset, payload.duration_sec, payload.title)
    logger.info(f"[ingest] Created session {session_obj.id} for asset {payload.asset_id}")

    await jobs.enqueue_transcription(db, session_obj)
    logger.info(f"[ingest] Enqueued transcription job for session {session_obj.id}")

    return {"sessionId": session_obj.id, "status": session_obj.status.value}

from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from ..models.entities import AudioAsset, User
from ..schemas.storage import UploadResponse, UploadUrlRequest, UploadUrlResponse
from ..services.storage import StorageService
from .deps import get_current_user, get_storage, get_db

router = APIRouter(tags=["storage"])


@router.post("/upload-url", response_model=UploadUrlResponse)
async def create_upload_url(
    payload: UploadUrlRequest,
    user: User = Depends(get_current_user),
) -> UploadUrlResponse:
    asset_id = str(uuid4())
    return UploadUrlResponse(uploadUrl="/upload", assetId=asset_id)


@router.post("/upload", response_model=UploadResponse)
async def upload_audio(
    file: UploadFile = File(...),
    assetId: str | None = Form(default=None),
    user: User = Depends(get_current_user),
    storage: StorageService = Depends(get_storage),
    db: AsyncSession = Depends(get_db),
) -> UploadResponse:
    asset_id, path = await storage.save(user.id, file, assetId)
    asset = AudioAsset(
        id=asset_id,
        user_id=user.id,
        path=str(path),
        filename=file.filename or f"{asset_id}.m4a",
        mime=file.content_type or "audio/m4a",
        size=path.stat().st_size,
    )
    db.add(asset)
    await db.commit()
    return UploadResponse(assetId=asset_id)

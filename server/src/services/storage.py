import shutil
from pathlib import Path
from typing import Protocol
from uuid import uuid4

from fastapi import UploadFile

from ..core.config import get_settings


class StorageService(Protocol):
    async def save(self, user_id: str, upload: UploadFile, asset_id: str | None = None) -> tuple[str, Path]:
        ...


class LocalStorageService:
    def __init__(self) -> None:
        self.settings = get_settings()

    async def save(self, user_id: str, upload: UploadFile, asset_id: str | None = None) -> tuple[str, Path]:
        target_dir = self.settings.media_root / user_id
        target_dir.mkdir(parents=True, exist_ok=True)
        extension = Path(upload.filename or "audio.m4a").suffix
        final_id = asset_id or str(uuid4())
        target_path = target_dir / f"{final_id}{extension}"
        with target_path.open("wb") as buffer:
            shutil.copyfileobj(upload.file, buffer)
        return final_id, target_path


def get_storage_service() -> StorageService:
    return LocalStorageService()

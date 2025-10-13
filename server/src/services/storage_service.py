from __future__ import annotations

import os
from pathlib import Path
from typing import BinaryIO
from uuid import uuid4

from fastapi import UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.config import get_settings
from ..models.audio_asset import AudioAsset
from ..models.user import User


class StorageService:
    def __init__(self) -> None:
        settings = get_settings().storage()
        self.media_root = settings.media_root
        self.media_root.mkdir(parents=True, exist_ok=True)

    def _build_path(self, user_id: int, filename: str) -> Path:
        extension = Path(filename).suffix or ".m4a"
        return self.media_root / str(user_id) / f"{uuid4().hex}{extension}"

    async def create_asset(self, session: AsyncSession, user: User, filename: str, mime: str) -> AudioAsset:
        path = self._build_path(user.id, filename)
        path.parent.mkdir(parents=True, exist_ok=True)
        asset = AudioAsset(user_id=user.id, path=str(path), filename=filename, mime=mime, size=0)
        session.add(asset)
        await session.commit()
        await session.refresh(asset)
        return asset

    async def save_upload(self, asset: AudioAsset, file: UploadFile) -> int:
        path = Path(asset.path)
        path.parent.mkdir(parents=True, exist_ok=True)
        size = 0
        with path.open("wb") as outfile:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                outfile.write(chunk)
                size += len(chunk)
        await file.close()
        return size

    async def update_asset_size(self, session: AsyncSession, asset: AudioAsset, size: int) -> AudioAsset:
        asset.size = size
        session.add(asset)
        await session.commit()
        await session.refresh(asset)
        return asset

    def open_binary(self, asset: AudioAsset) -> BinaryIO:
        return Path(asset.path).open("rb")

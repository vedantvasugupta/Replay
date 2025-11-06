from __future__ import annotations

import logging
import os
from pathlib import Path
from typing import BinaryIO
from uuid import uuid4

from fastapi import UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from ..core.config import get_settings
from ..models.audio_asset import AudioAsset
from ..models.user import User

logger = logging.getLogger(__name__)


class StorageService:
    def __init__(self) -> None:
        settings = get_settings().storage()
        self.media_root = settings.media_root
        self.media_root.mkdir(parents=True, exist_ok=True)
        # Always work with an absolute media root path for consistency across OSes.
        self.media_root = self.media_root.resolve()

    def _build_path(self, user_id: int, filename: str) -> Path:
        extension = Path(filename).suffix or ".m4a"
        return self.media_root / str(user_id) / f"{uuid4().hex}{extension}"

    def _normalize_asset_path(self, asset: AudioAsset) -> Path:
        """Normalize stored asset paths and return the absolute filesystem location."""
        raw_path = (asset.path or "").strip()
        normalized = raw_path.replace("\\", "/")
        if normalized.startswith("./"):
            normalized = normalized[2:]

        path = Path(normalized) if normalized else Path()
        resolved: Path
        stored_value: str

        if path.is_absolute():
            try:
                parts = list(path.relative_to(self.media_root).parts)
            except ValueError:
                resolved = path.resolve()
                stored_value = resolved.as_posix()
            else:
                resolved = (self.media_root.joinpath(*parts)).resolve()
                stored_value = "/".join(parts)
        else:
            parts = list(path.parts)
            media_root_name = self.media_root.name
            if parts and parts[0] == media_root_name:
                parts = parts[1:]
            resolved = (self.media_root.joinpath(*parts)).resolve()
            stored_value = "/".join(parts)

        if asset.path != stored_value:
            asset.path = stored_value
        return resolved

    def resolve_asset_path(self, asset: AudioAsset) -> Path:
        """Public helper so other services can resolve normalized paths."""
        return self._normalize_asset_path(asset)

    async def create_asset(self, session: AsyncSession, user: User, filename: str, mime: str) -> AudioAsset:
        path = self._build_path(user.id, filename)
        path.parent.mkdir(parents=True, exist_ok=True)
        relative_parts = list(path.relative_to(self.media_root).parts)
        stored_path = "/".join(relative_parts)
        asset = AudioAsset(user_id=user.id, path=stored_path, filename=filename, mime=mime, size=0)
        session.add(asset)
        await session.commit()
        await session.refresh(asset)
        return asset

    async def save_upload(self, asset: AudioAsset, file: UploadFile) -> int:
        path = self._normalize_asset_path(asset)
        logger.info(f"[save_upload] Saving asset {asset.id} to {path}")
        logger.info(f"[save_upload] File object: filename={file.filename}, content_type={file.content_type}")

        path.parent.mkdir(parents=True, exist_ok=True)
        logger.info(f"[save_upload] Created directory: {path.parent}")

        size = 0
        chunks_read = 0
        with path.open("wb") as outfile:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    logger.info(f"[save_upload] No more chunks to read after {chunks_read} chunks")
                    break
                outfile.write(chunk)
                size += len(chunk)
                chunks_read += 1
                if chunks_read == 1:
                    logger.info(f"[save_upload] First chunk size: {len(chunk)} bytes")

        await file.close()
        logger.info(f"[save_upload] Wrote {size} bytes in {chunks_read} chunks to {path}")

        # Verify the file was written
        if path.exists():
            actual_size = path.stat().st_size
            logger.info(f"[save_upload] File exists on disk with size: {actual_size} bytes")
            if actual_size != size:
                logger.error(f"[save_upload] SIZE MISMATCH! Wrote {size} bytes but file is {actual_size} bytes")
        else:
            logger.error(f"[save_upload] File does not exist after write: {path}")

        return size

    async def update_asset_size(self, session: AsyncSession, asset: AudioAsset, size: int) -> AudioAsset:
        asset.size = size
        session.add(asset)
        await session.commit()
        await session.refresh(asset)
        return asset

    def open_binary(self, asset: AudioAsset) -> BinaryIO:
        path = self._normalize_asset_path(asset)
        return path.open("rb")

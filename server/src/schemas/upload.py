from __future__ import annotations

from pydantic import Field, ConfigDict

from .base import CamelModel


class UploadUrlRequest(CamelModel):
    filename: str
    mime: str = Field(pattern=r"audio/[\w\-\+\.]+")

    model_config = ConfigDict(populate_by_name=True)


class UploadUrlResponse(CamelModel):
    model_config = ConfigDict(populate_by_name=True)

    upload_url: str = Field(alias="uploadUrl")
    asset_id: int = Field(alias="assetId")


class UploadIngestRequest(CamelModel):
    model_config = ConfigDict(populate_by_name=True)

    asset_id: int = Field(alias="assetId")
    duration_sec: int | None = None
    title: str | None = None

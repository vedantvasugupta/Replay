from pydantic import BaseModel


class UploadUrlRequest(BaseModel):
    filename: str
    mime: str


class UploadUrlResponse(BaseModel):
    uploadUrl: str
    assetId: str


class UploadResponse(BaseModel):
    assetId: str

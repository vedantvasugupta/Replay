from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal, Optional

from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class JwtSettings(BaseModel):
    secret_key: str
    access_expires_minutes: int = Field(default=525600, ge=1)  # 1 year (365 * 24 * 60)
    refresh_expires_days: int = Field(default=365, ge=1)  # 1 year
    algorithm: str = "HS256"


class GeminiSettings(BaseModel):
    project_id: str
    location: str = "us-central1"
    model: str = "gemini-2.5-pro"
    api_key: Optional[str] = None


class StorageSettings(BaseModel):
    provider: Literal["local"] = "local"
    media_root: Path = Path("./media")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env",),
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    database_url: str = Field(alias="DATABASE_URL")
    jwt_secret: str = Field(alias="JWT_SECRET")
    access_expires_min: int = Field(default=525600, alias="ACCESS_EXPIRES_MIN")  # 1 year
    refresh_expires_days: int = Field(default=365, alias="REFRESH_EXPIRES_DAYS")  # 1 year
    storage_provider: Literal["local"] = Field(default="local", alias="STORAGE_PROVIDER")
    media_root: Path = Field(default=Path("./media"), alias="MEDIA_ROOT")
    gemini_project: str = Field(alias="GEMINI_PROJECT")
    gemini_location: str = Field(default="us-central1", alias="GEMINI_LOCATION")
    gemini_model: str = Field(default="gemini-2.5-pro", alias="GEMINI_MODEL")
    gemini_api_key: Optional[str] = Field(default=None, alias="GEMINI_API_KEY")
    background_poll_interval: int = Field(default=5, alias="BACKGROUND_POLL_INTERVAL")
    background_worker_concurrency: int = Field(
        default=2,
        ge=1,
        alias="BACKGROUND_WORKER_CONCURRENCY",
    )

    def jwt(self) -> JwtSettings:
        return JwtSettings(
            secret_key=self.jwt_secret,
            access_expires_minutes=self.access_expires_min,
            refresh_expires_days=self.refresh_expires_days,
        )

    def gemini(self) -> GeminiSettings:
        return GeminiSettings(
            project_id=self.gemini_project,
            location=self.gemini_location,
            model=self.gemini_model,
            api_key=self.gemini_api_key,
        )

    def storage(self) -> StorageSettings:
        return StorageSettings(provider=self.storage_provider, media_root=self.media_root)


@lru_cache
def get_settings() -> Settings:
    return Settings()

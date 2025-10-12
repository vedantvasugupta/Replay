from functools import lru_cache
from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    environment: str = "dev"
    database_url: str
    jwt_secret: str
    access_expires_min: int = 15
    refresh_expires_days: int = 7
    gemini_project: str = ""
    gemini_location: str = "us-central1"
    gemini_model: str = "gemini-2.5-pro"
    storage_provider: str = "local"
    media_root: Path = Path("./media")

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", case_sensitive=False)


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    settings.media_root.mkdir(parents=True, exist_ok=True)
    return settings

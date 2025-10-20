from __future__ import annotations

from src.core.config import get_settings
from src.models.audio_asset import AudioAsset
from src.services.storage_service import StorageService


def test_resolve_asset_path_normalizes_windows_style_paths(monkeypatch, tmp_path) -> None:
    # Override MEDIA_ROOT for this test to ensure isolation.
    monkeypatch.setenv("MEDIA_ROOT", str(tmp_path))
    get_settings.cache_clear()

    storage = StorageService()

    # Simulate an asset stored with Windows-style separators.
    raw_path = f"{tmp_path}\\1\\demo.m4a"
    asset = AudioAsset(user_id=1, path=raw_path, filename="demo.m4a", mime="audio/m4a", size=0)

    resolved = storage.resolve_asset_path(asset)

    assert resolved == tmp_path / "1" / "demo.m4a"
    # Stored path should use POSIX separators relative to the media root.
    assert asset.path == "1/demo.m4a"

    # Reset cached settings for subsequent tests.
    get_settings.cache_clear()

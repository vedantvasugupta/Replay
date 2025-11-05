#!/usr/bin/env python3
"""
Test upload flow manually
Run this on the server via: python scripts/test_upload.py
"""

import asyncio
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from io import BytesIO
from fastapi import UploadFile
from sqlalchemy import select

from core.db import sessionmaker
from models.audio_asset import AudioAsset
from models.user import User
from services.storage_service import StorageService


async def test_upload():
    """Test the upload flow with a dummy file"""
    print("=" * 80)
    print("TESTING UPLOAD FLOW")
    print("=" * 80)

    storage = StorageService()
    print(f"Storage media root: {storage.media_root}")
    print(f"Media root exists: {storage.media_root.exists()}")
    print()

    async with sessionmaker() as db:
        # Get the first user
        result = await db.execute(select(User).limit(1))
        user = result.scalar_one_or_none()

        if not user:
            print("❌ No users found in database!")
            return

        print(f"✅ Found user: {user.email} (ID: {user.id})")

        # Create a test asset
        print("\n1. Creating test asset...")
        asset = await storage.create_asset(db, user, "test_upload.m4a", "audio/m4a")
        print(f"✅ Created asset {asset.id} at path: {asset.path}")
        print(f"   Initial size: {asset.size}")

        # Create a dummy file with some data
        print("\n2. Creating dummy upload file...")
        test_data = b"This is test audio data " * 1000  # ~24KB of data
        test_file = BytesIO(test_data)

        # Create UploadFile wrapper
        upload_file = UploadFile(
            filename="test_upload.m4a",
            file=test_file,
        )

        print(f"✅ Created test file with {len(test_data)} bytes")

        # Save the upload
        print("\n3. Saving upload...")
        try:
            saved_size = await storage.save_upload(asset, upload_file)
            print(f"✅ save_upload returned: {saved_size} bytes")

            # Update asset size
            print("\n4. Updating asset size in DB...")
            await storage.update_asset_size(db, asset, saved_size)
            print(f"✅ Updated asset {asset.id} size to {saved_size}")

            # Verify the file on disk
            print("\n5. Verifying file on disk...")
            normalized_path = asset.path.replace("\\", "/")
            if normalized_path.startswith("./"):
                normalized_path = normalized_path[2:]
            file_path = storage.media_root / normalized_path

            if file_path.exists():
                actual_size = file_path.stat().st_size
                print(f"✅ File exists: {file_path}")
                print(f"   Actual size: {actual_size} bytes")

                if actual_size == saved_size == len(test_data):
                    print("✅ SUCCESS! All sizes match!")
                else:
                    print(f"❌ SIZE MISMATCH!")
                    print(f"   Expected: {len(test_data)}")
                    print(f"   Saved: {saved_size}")
                    print(f"   On disk: {actual_size}")
            else:
                print(f"❌ File does not exist: {file_path}")

        except Exception as e:
            print(f"❌ Error during upload: {e}")
            import traceback
            traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(test_upload())

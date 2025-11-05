#!/usr/bin/env python3
"""
Debug script to investigate 0-byte upload issue
Run this on the server via: python scripts/debug_uploads.py
"""

import asyncio
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from sqlalchemy import select, desc
from sqlalchemy.ext.asyncio import AsyncSession

from core.config import get_settings
from core.db import engine, sessionmaker
from models.audio_asset import AudioAsset
from models.session import Session
from models.user import User


async def debug_uploads():
    """Main debugging function"""
    print("=" * 80)
    print("UPLOAD DEBUG REPORT")
    print("=" * 80)
    print(f"Timestamp: {datetime.now()}")
    print()

    # Get settings
    settings = get_settings()
    storage_settings = settings.storage()
    media_root = storage_settings.media_root.resolve()

    print(f"Media Root: {media_root}")
    print(f"Media Root Exists: {media_root.exists()}")
    print()

    # Check database
    async with sessionmaker() as db:
        # Get recent assets (last 24 hours)
        cutoff = datetime.now() - timedelta(hours=24)
        result = await db.execute(
            select(AudioAsset, User)
            .join(User, AudioAsset.user_id == User.id)
            .order_by(desc(AudioAsset.created_at))
            .limit(20)
        )
        assets = result.all()

        print(f"📊 RECENT AUDIO ASSETS (last 20):")
        print("-" * 80)

        if not assets:
            print("No assets found in database!")
            return

        for asset, user in assets:
            print(f"\nAsset ID: {asset.id}")
            print(f"  User: {user.email} (ID: {user.id})")
            print(f"  Filename: {asset.filename}")
            print(f"  MIME: {asset.mime}")
            print(f"  DB Size: {asset.size} bytes")
            print(f"  Path (stored): {asset.path}")
            print(f"  Created: {asset.created_at}")

            # Check if file exists on disk
            if asset.path:
                # Normalize the path
                normalized = asset.path.replace("\\", "/")
                if normalized.startswith("./"):
                    normalized = normalized[2:]

                file_path = media_root / normalized
                print(f"  Full Path: {file_path}")
                print(f"  File Exists: {file_path.exists()}")

                if file_path.exists():
                    actual_size = file_path.stat().st_size
                    print(f"  Actual File Size: {actual_size} bytes")

                    if actual_size != asset.size:
                        print(f"  ⚠️  SIZE MISMATCH! DB says {asset.size}, disk has {actual_size}")

                    if actual_size == 0:
                        print(f"  ❌ PROBLEM: File is 0 bytes on disk!")

                        # Check file permissions
                        stat_info = file_path.stat()
                        print(f"  File Permissions: {oct(stat_info.st_mode)}")
                        print(f"  File Owner: UID {stat_info.st_uid}, GID {stat_info.st_gid}")
                else:
                    print(f"  ❌ PROBLEM: File does not exist on disk!")
            else:
                print(f"  ❌ PROBLEM: No path stored in database!")

            # Check if there's an associated session
            session_result = await db.execute(
                select(Session).where(Session.audio_asset_id == asset.id)
            )
            session = session_result.scalar_one_or_none()

            if session:
                print(f"  Session: {session.id} - Status: {session.status.value}")
            else:
                print(f"  Session: None (not ingested yet)")

        print("\n" + "=" * 80)
        print("📁 FILE SYSTEM CHECK:")
        print("-" * 80)

        # List all files in media root
        if media_root.exists():
            print(f"\nScanning {media_root}...")
            all_files = []
            for root, dirs, files in os.walk(media_root):
                for file in files:
                    file_path = Path(root) / file
                    size = file_path.stat().st_size
                    all_files.append((file_path, size))

            print(f"Total files found: {len(all_files)}")

            # Show 0-byte files
            zero_byte_files = [(p, s) for p, s in all_files if s == 0]
            if zero_byte_files:
                print(f"\n❌ Found {len(zero_byte_files)} zero-byte files:")
                for path, size in zero_byte_files[:10]:  # Show first 10
                    print(f"  - {path}")
            else:
                print("\n✅ No zero-byte files found!")

            # Show file size distribution
            total_size = sum(s for _, s in all_files)
            print(f"\nTotal storage used: {total_size / (1024*1024):.2f} MB")

            if all_files:
                avg_size = total_size / len(all_files)
                print(f"Average file size: {avg_size / 1024:.2f} KB")
        else:
            print(f"❌ Media root does not exist: {media_root}")

        print("\n" + "=" * 80)
        print("🔍 ANALYSIS:")
        print("-" * 80)

        # Count issues
        zero_db = sum(1 for asset, _ in assets if asset.size == 0)
        print(f"Assets with 0 bytes in DB: {zero_db} out of {len(assets)}")

        missing_files = 0
        for asset, _ in assets:
            if asset.path:
                normalized = asset.path.replace("\\", "/")
                if normalized.startswith("./"):
                    normalized = normalized[2:]
                file_path = media_root / normalized
                if not file_path.exists():
                    missing_files += 1

        print(f"Assets with missing files: {missing_files} out of {len(assets)}")

        print("\n" + "=" * 80)
        print("💡 RECOMMENDATIONS:")
        print("-" * 80)

        if zero_db > 0:
            print("1. Assets with 0 bytes in DB suggest the /upload endpoint")
            print("   is not being called or is failing silently.")
            print("2. Check server logs for upload errors")
            print("3. Verify client is actually calling /upload endpoint")
            print("4. Check network connectivity and timeout settings")

        if missing_files > 0:
            print("5. Missing files suggest storage issues or cleanup")
            print("   Check if files are being deleted prematurely")

        if zero_byte_files:
            print("6. Zero-byte files on disk suggest write failures")
            print("   Check disk space, permissions, and I/O errors")


if __name__ == "__main__":
    asyncio.run(debug_uploads())

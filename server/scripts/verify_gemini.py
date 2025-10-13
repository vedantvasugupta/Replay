"""
Utility to verify the configured Gemini API key.

Usage:
    python -m scripts.verify_gemini

The script loads the backend settings, instantiates GeminiService, and sends
a small summarisation request. A successful response confirms that the API key
is valid and reachable from the current environment.
"""

from __future__ import annotations

import asyncio
import sys

from httpx import HTTPError

from src.services.gemini_service import GeminiService


async def _run_check() -> int:
    service = GeminiService()
    if not service.api_key:
        print("✗ GEMINI_API_KEY is not configured (value missing or empty).")
        return 1

    sample_text = (
        "Daily stand-up transcript: Alice reported finishing the login UI. "
        "Bob is blocked on the API response schema. Carol will help Bob."
    )
    try:
        result = await service.summarize(sample_text)
    except HTTPError as exc:
        print(f"✗ Gemini API call failed: {exc}")
        if exc.response is not None:
            print(f"  Status: {exc.response.status_code}")
            try:
                print(f"  Response body: {exc.response.text}")
            except Exception:
                pass
        return 1
    except Exception as exc:  # pragma: no cover - defensive
        print(f"✗ Unexpected error contacting Gemini: {exc}")
        return 1

    summary = result.get("summary") or "<empty summary>"
    print("✓ Gemini API call succeeded.")
    print(f"  Summary preview: {summary[:120]}")
    return 0


def main() -> None:
    exit_code = asyncio.run(_run_check())
    sys.exit(exit_code)


if __name__ == "__main__":
    main()

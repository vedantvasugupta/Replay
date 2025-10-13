from __future__ import annotations

import uvicorn

from .app import app


def run() -> None:
    uvicorn.run("src.app:app", host="0.0.0.0", port=8000, reload=True)


if __name__ == "__main__":
    run()

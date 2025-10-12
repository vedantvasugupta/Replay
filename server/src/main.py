from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api import auth, sessions, upload
from .services.jobs import jobs_service

app = FastAPI(title="Replay API", version="0.1.0")

app.include_router(auth.router)
app.include_router(upload.router)
app.include_router(sessions.router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup_event() -> None:
    await jobs_service.start()


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}

"""FastAPI application entrypoint.

Run locally:
    cd backend && uvicorn app.main:app --reload
"""
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import health, players, sync
from app.core.config import settings
from app.services.scheduler import scheduler


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Starts the periodic Sportradar sync only when it is fully configured and
    # enabled; otherwise this is a no-op and the app serves existing data. Under
    # a multi-worker server only the worker with enable_scheduler set runs it,
    # so the sync doesn't fan out to every process.
    if settings.enable_scheduler:
        scheduler.start()
    try:
        yield
    finally:
        await scheduler.stop()


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        description="Backend API for Hoop Archive — NBA historical & current player analytics.",
        lifespan=lifespan,
    )

    # The Flutter client may run from a device/emulator; CORS is permissive in
    # development. Tighten allow_origins for production deployments.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(health.router)
    app.include_router(players.router)
    app.include_router(sync.router)
    return app


app = create_app()

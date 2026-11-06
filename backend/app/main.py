"""FastAPI application entrypoint.

Run locally:
    cd backend && uvicorn app.main:app --reload
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import health
from app.core.config import settings


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        version="0.1.0",
        description="Backend API for Hoop Archive — NBA historical & current player analytics.",
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
    return app


app = create_app()

"""Standalone gaze service for the PC path: `uvicorn eyetracking.gaze.main:app --port 8100`."""
from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .service import build_router, estimator_from_env


def create_gaze_app() -> FastAPI:
    app = FastAPI(title="EyeTracking gaze service", version="0.1.0")
    app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
    app.include_router(build_router(estimator_from_env()))
    return app


app = create_gaze_app()

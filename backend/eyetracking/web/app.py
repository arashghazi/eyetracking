"""Composition root: builds the FastAPI application from settings."""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from eyetracking.application import use_cases
from eyetracking.domain.errors import AuthenticationFailed, Conflict, DomainError, Forbidden, Invalid, NotFound
from eyetracking.infrastructure.media import LocalMediaStore
from eyetracking.infrastructure.security import Argon2Hasher, HmacMediaSigner, JwtTokens, SystemClock
from eyetracking.infrastructure.uow import SqlUnitOfWork, create_schema, make_engine, session_factory_for

from .routers import ai, auth, participant, practice, research, sessions, studies
from .settings import Settings

_STATUS = {NotFound: 404, Forbidden: 403, Conflict: 409, Invalid: 422, AuthenticationFailed: 401}


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings()
    engine = make_engine(settings.database_url)
    create_schema(engine)
    session_factory = session_factory_for(engine)
    hasher = Argon2Hasher()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        if settings.bootstrap_admin_email and settings.bootstrap_admin_password:
            uow = SqlUnitOfWork(session_factory)
            try:
                use_cases.bootstrap_admin(uow, hasher, settings.bootstrap_admin_email, settings.bootstrap_admin_password)
            finally:
                uow.close()
        worker = getattr(app.state, "ai_worker", None)
        if worker is not None:
            worker.start()
        yield
        if worker is not None:
            worker.stop()

    app = FastAPI(title="EyeTracking practice API", version="0.1.0", lifespan=lifespan)
    app.state.settings = settings
    app.state.engine = engine
    app.state.session_factory = session_factory
    app.state.hasher = hasher
    app.state.tokens = JwtTokens(settings.jwt_secret, settings.jwt_expire_minutes)
    app.state.clock = SystemClock()
    app.state.media_store = LocalMediaStore(settings.media_dir)
    app.state.media_signer = HmacMediaSigner(settings.jwt_secret, settings.media_url_ttl_seconds)
    app.state.ai_providers = _build_ai_providers(settings)
    app.state.ai_worker = None
    if settings.ai_worker_enabled:
        from eyetracking.infrastructure.ai.worker import AiWorker

        app.state.ai_worker = AiWorker(session_factory, app.state.ai_providers, app.state.media_store, app.state.clock, settings.ai_worker_interval_s)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.exception_handler(DomainError)
    async def domain_error(_: Request, exc: DomainError):
        status = next((code for cls, code in _STATUS.items() if isinstance(exc, cls)), 400)
        return JSONResponse(status_code=status, content={"detail": str(exc)})

    @app.get("/health", tags=["meta"])
    def health():
        return {"status": "ok"}

    app.include_router(auth.router)
    app.include_router(research.router)
    app.include_router(participant.router)
    app.include_router(studies.router)
    app.include_router(sessions.router)
    app.include_router(practice.router)
    app.include_router(ai.router)
    if settings.gaze_in_api:
        from fastapi import Depends

        from eyetracking.gaze.service import build_router, estimator_from_env

        from .deps import get_principal

        # Secure path for phones: same estimator surface, bearer token required, frames never stored.
        app.include_router(build_router(estimator_from_env()), prefix="/gaze", dependencies=[Depends(get_principal)])
    return app


def _build_ai_providers(settings: Settings):
    """Providers from settings; the fake ones need no key. Real adapters are only used when configured."""
    from eyetracking.application.ai_use_cases import Providers
    from eyetracking.infrastructure.ai.fake import FakeTextGenerator, FakeVideoGenerator

    if settings.ai_text_provider == "anthropic":
        from eyetracking.infrastructure.ai.anthropic_text import AnthropicTextGenerator

        text = AnthropicTextGenerator(settings.anthropic_api_key, settings.ai_text_model)
    else:
        text = FakeTextGenerator()
    if settings.ai_video_provider == "heygen":
        from eyetracking.infrastructure.ai.heygen_video import HeyGenVideoGenerator

        video = HeyGenVideoGenerator(settings.heygen_api_key, settings.heygen_base_url, settings.heygen_cost_per_minute_units)
    else:
        video = FakeVideoGenerator()
    return Providers(text=text, video=video, worker_enabled=settings.ai_worker_enabled, worker_interval_s=settings.ai_worker_interval_s)

"""FastAPI dependencies: unit of work, adapters and the authenticated principal."""
from __future__ import annotations

from collections.abc import Iterator

from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from eyetracking.application import use_cases
from eyetracking.application.authz import Principal
from eyetracking.infrastructure.security import Argon2Hasher, JwtTokens, SystemClock
from eyetracking.infrastructure.uow import SqlUnitOfWork

bearer = HTTPBearer(auto_error=False)


def get_uow(request: Request) -> Iterator[SqlUnitOfWork]:
    uow = SqlUnitOfWork(request.app.state.session_factory)
    try:
        yield uow
    finally:
        uow.close()


def get_hasher(request: Request) -> Argon2Hasher:
    return request.app.state.hasher


def get_tokens(request: Request) -> JwtTokens:
    return request.app.state.tokens


def get_clock(request: Request) -> SystemClock:
    return request.app.state.clock


def get_principal(
    creds: HTTPAuthorizationCredentials | None = Depends(bearer),
    uow: SqlUnitOfWork = Depends(get_uow),
    tokens: JwtTokens = Depends(get_tokens),
) -> Principal:
    if creds is None:
        raise HTTPException(status_code=401, detail="authentication required")
    user_id = tokens.parse(creds.credentials)
    principal = use_cases.load_principal(uow, user_id) if user_id is not None else None
    if principal is None:
        raise HTTPException(status_code=401, detail="invalid or expired token")
    return principal

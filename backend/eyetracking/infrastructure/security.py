from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt
from argon2 import PasswordHasher as _Argon2
from argon2.exceptions import VerifyMismatchError


class Argon2Hasher:
    def __init__(self) -> None:
        self._ph = _Argon2()

    def hash(self, password: str) -> str:
        return self._ph.hash(password)

    def verify(self, password: str, password_hash: str) -> bool:
        try:
            return self._ph.verify(password_hash, password)
        except VerifyMismatchError:
            return False
        except Exception:
            return False


class JwtTokens:
    def __init__(self, secret: str, expire_minutes: int = 120):
        self._secret = secret
        self._minutes = expire_minutes

    def issue(self, user_id: int, role: str) -> str:
        now = datetime.now(timezone.utc)
        payload = {"sub": str(user_id), "role": role, "iat": now, "exp": now + timedelta(minutes=self._minutes)}
        return jwt.encode(payload, self._secret, algorithm="HS256")

    def parse(self, token: str) -> int | None:
        try:
            payload = jwt.decode(token, self._secret, algorithms=["HS256"])
            return int(payload["sub"])
        except Exception:
            return None


class SystemClock:
    def now(self) -> datetime:
        return datetime.utcnow()

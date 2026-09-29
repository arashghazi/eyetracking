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


class HmacMediaSigner:
    """Short-lived, signed media tokens: base64url(json{m, e}) + '.' + hmac. No database lookup to verify."""

    def __init__(self, secret: str, ttl_seconds: int = 6 * 3600):
        self._key = secret.encode()
        self._ttl = ttl_seconds

    def sign(self, media_id: int) -> str:
        import base64
        import hmac
        import json
        import time

        payload = base64.urlsafe_b64encode(json.dumps({"m": int(media_id), "e": int(time.time()) + self._ttl}).encode()).decode().rstrip("=")
        mac = hmac.new(self._key, payload.encode(), "sha256").hexdigest()
        return f"{payload}.{mac}"

    def verify(self, token: str) -> int | None:
        import base64
        import hmac
        import json
        import time

        try:
            payload, mac = token.split(".", 1)
            expected = hmac.new(self._key, payload.encode(), "sha256").hexdigest()
            if not hmac.compare_digest(mac, expected):
                return None
            data = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
            if int(data["e"]) < time.time():
                return None
            return int(data["m"])
        except Exception:
            return None

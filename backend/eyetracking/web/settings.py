from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration. Values come from environment variables or a local .env file."""

    model_config = SettingsConfigDict(env_prefix="EYETRACKING_", env_file=".env", extra="ignore")

    database_url: str = "sqlite:///./eyetracking_dev.db"
    jwt_secret: str = "change-me-in-production"
    jwt_expire_minutes: int = 120
    bootstrap_admin_email: str | None = None
    bootstrap_admin_password: str | None = None
    cors_origins: list[str] = ["http://localhost:8080", "http://localhost:5173", "http://localhost:3000"]

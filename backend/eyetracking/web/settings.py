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
    gaze_in_api: bool = True
    media_dir: str = "./media"
    media_url_ttl_seconds: int = 6 * 3600
    # AI content generation (step 5); keys never leave the server
    ai_text_provider: str = "fake"  # fake | anthropic
    ai_text_model: str = "claude-opus-5-5"
    anthropic_api_key: str | None = None
    ai_video_provider: str = "fake"  # fake | heygen
    heygen_api_key: str | None = None
    heygen_base_url: str = "https://api.heygen.com"
    heygen_cost_per_minute_units: float = 1.0
    ai_worker_enabled: bool = False
    ai_worker_interval_s: int = 5

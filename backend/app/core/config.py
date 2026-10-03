from __future__ import annotations

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    app_name: str = Field(default="StrollWise API")
    env: str = Field(default="development")
    debug: bool = Field(default=True)
    api_v1_prefix: str = Field(default="/api/v1")

    database_url: str = Field(
        default="postgresql+psycopg2://strollwise:strollwise@localhost:5432/strollwise"
    )
    redis_url: str = Field(default="redis://localhost:6379/0")

    jwt_secret_key: str = Field(default="change-me-in-production")
    jwt_algorithm: str = Field(default="HS256")
    access_token_expire_minutes: int = Field(default=60 * 24 * 7)

    h3_resolution: int = Field(default=8)
    # Cap how many H3 cells can expand a place/zone footprint (prevents city-wide blobs).
    max_h3_cells_per_place: int = Field(default=24)
    city_center_lat: float = Field(default=10.3157)
    city_center_lng: float = Field(default=123.8854)

    mapbox_access_token: str | None = Field(default=None)
    mapbox_style: str = Field(default="mapbox/streets-v12")

    cache_ttl_zones_seconds: int = Field(default=60)
    cache_ttl_zone_feed_seconds: int = Field(default=25)
    cache_ttl_pulse_seconds: int = Field(default=120)
    pending_cache_ttl_seconds: int = Field(default=900)
    # Minimum distinct people (unique reporters) in the same H3 cell before it
    # can form / go public, plus category agreement in report_service.
    pending_min_reports_per_cell: int = Field(default=3)
    pending_agreement_ratio: float = Field(default=0.6)
    # Per-user anti-spam on POST /reports (0 disables that guard).
    report_cooldown_hours_per_cell: int = Field(default=24)
    report_max_per_user_per_hour: int = Field(default=30)

    s3_bucket_name: str | None = Field(default=None)
    s3_access_key: str | None = Field(default=None)
    s3_secret_key: str | None = Field(default=None)
    s3_region: str = Field(default="us-east-1")
    upload_local_dir: str = Field(default="/tmp/strollwise-uploads")

    cors_origins: str = Field(
        default="http://localhost:5173,http://127.0.0.1:5173,http://localhost:8000,http://127.0.0.1:8000"
    )

    @property
    def cors_origin_list(self) -> list[str]:
        raw = self.cors_origins.strip()
        if not raw or raw == "*":
            return [
                "http://localhost:5173",
                "http://127.0.0.1:5173",
                "http://localhost:8000",
                "http://127.0.0.1:8000",
                "http://localhost:53080",
                "http://127.0.0.1:53080",
            ]
        origins = [origin.strip() for origin in raw.split(",") if origin.strip()]
        return origins if origins else ["http://localhost:5173"]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env", ".env.local"),
        env_prefix="NEXAIQ_",
        extra="ignore",
    )

    environment: str = "development"
    max_estimate_bytes: int = 15 * 1024 * 1024
    allowed_origins_raw: str = Field(
        default="http://localhost:3000", alias="NEXAIQ_ALLOWED_ORIGINS"
    )
    max_pdf_pages: int = 250
    max_capture_photo_bytes: int = 8 * 1024 * 1024
    max_capture_voice_bytes: int = 20 * 1024 * 1024
    supabase_url: str | None = Field(default=None, alias="SUPABASE_URL")
    supabase_publishable_key: str | None = Field(default=None, alias="SUPABASE_PUBLISHABLE_KEY")
    supabase_secret_key: str | None = Field(default=None, alias="SUPABASE_SECRET_KEY")
    openai_api_key: str | None = Field(default=None, alias="OPENAI_API_KEY")
    openai_base_url: str = Field(default="https://api.openai.com/v1", alias="OPENAI_BASE_URL")
    ai_request_timeout_seconds: int = 120
    max_analysis_photos: int = 8
    max_analysis_photo_bytes: int = 24 * 1024 * 1024

    @property
    def allowed_origins(self) -> list[str]:
        return [origin.strip() for origin in self.allowed_origins_raw.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()

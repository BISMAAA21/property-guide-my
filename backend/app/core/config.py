from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=("../.env", ".env"),
        env_file_encoding="utf-8",
        env_ignore_empty=True,
        extra="ignore",
    )

    app_env: Literal["development", "test", "production"] = "development"
    log_level: str = "INFO"
    preload_vision_models: bool = False
    baked_clip_model_id: str | None = Field(default=None, min_length=1, max_length=200)
    firebase_project_id: str | None = None
    firebase_api_key: str | None = Field(default=None, repr=False)
    google_application_credentials: Path | None = Field(default=None, repr=False)
    seed_user_password: str | None = Field(default=None, repr=False, min_length=12)
    gemini_api_key: str | None = Field(default=None, repr=False)
    gemini_model: str = Field(default="gemini-3.5-flash-lite", min_length=1, max_length=200)
    vision_model_id: str = Field(
        default="openai/clip-vit-base-patch32", min_length=1, max_length=200
    )
    damage_model_id: str = Field(
        default="openai/clip-vit-base-patch32", min_length=1, max_length=200
    )
    damage_min_confidence: float | None = None
    image_similarity_high_threshold: float | None = None
    image_similarity_moderate_threshold: float | None = None
    max_image_bytes: int = Field(default=10 * 1024 * 1024, ge=1, le=50 * 1024 * 1024)
    max_listing_images: int = Field(default=8, ge=1, le=20)
    max_pdf_bytes: int = Field(default=10 * 1024 * 1024, ge=1, le=50 * 1024 * 1024)
    max_pdf_pages: int = Field(default=30, ge=1, le=100)
    tesseract_cmd: Path | None = Field(default=None, repr=False)
    ocr_min_embedded_text_chars: int = Field(default=40, ge=1, le=10_000)
    ocr_language: str = Field(default="eng", pattern=r"^[A-Za-z0-9_+.-]{2,40}$")
    ocr_timeout_seconds: int = Field(default=20, ge=1, le=120)
    agreement_provider_timeout_seconds: int = Field(default=45, ge=1, le=300)
    agreement_provider_batch_size: int = Field(default=12, ge=1, le=25)
    max_agreement_clauses: int = Field(default=100, ge=1, le=200)
    max_agreement_text_chars: int = Field(default=120_000, ge=1, le=500_000)

    @field_validator("google_application_credentials", "tesseract_cmd", mode="before")
    @classmethod
    def empty_optional_path_is_none(cls, value: object) -> object:
        if isinstance(value, str) and value.strip() == "":
            return None
        return value

    @property
    def image_similarity_thresholds_are_valid(self) -> bool:
        high = self.image_similarity_high_threshold
        moderate = self.image_similarity_moderate_threshold
        return high is not None and moderate is not None and 0 <= moderate < high <= 100

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    def validate_runtime_configuration(self) -> None:
        """Fail fast when a production service cannot support the assessed modules."""
        if not self.is_production:
            return

        missing: list[str] = []
        if not self.firebase_project_id:
            missing.append("FIREBASE_PROJECT_ID")
        if not self.gemini_api_key:
            missing.append("GEMINI_API_KEY")
        if not self.image_similarity_thresholds_are_valid:
            missing.extend(
                [
                    "IMAGE_SIMILARITY_HIGH_THRESHOLD",
                    "IMAGE_SIMILARITY_MODERATE_THRESHOLD",
                ]
            )
        if self.damage_min_confidence is None or not 0 < self.damage_min_confidence <= 1:
            missing.append("DAMAGE_MIN_CONFIDENCE")
        if missing:
            fields = ", ".join(dict.fromkeys(missing))
            raise RuntimeError(f"Production configuration is incomplete: {fields}.")
        if self.seed_user_password:
            raise RuntimeError("SEED_USER_PASSWORD must not be configured in production.")
        if self.baked_clip_model_id and (
            self.vision_model_id != self.baked_clip_model_id
            or self.damage_model_id != self.baked_clip_model_id
        ):
            raise RuntimeError(
                "VISION_MODEL_ID and DAMAGE_MODEL_ID must match BAKED_CLIP_MODEL_ID."
            )


@lru_cache
def get_settings() -> Settings:
    return Settings()

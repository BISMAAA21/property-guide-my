import pytest
from pydantic import ValidationError

from app.core.config import Settings


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("max_image_bytes", 0),
        ("max_listing_images", 21),
        ("max_pdf_pages", 0),
        ("ocr_timeout_seconds", 121),
        ("agreement_provider_timeout_seconds", 0),
        ("agreement_provider_batch_size", 26),
        ("max_agreement_clauses", 201),
        ("max_agreement_text_chars", 0),
    ],
)
def test_unsafe_resource_limit_configuration_is_rejected(
    field: str,
    value: int,
) -> None:
    with pytest.raises(ValidationError):
        Settings(**{field: value})


@pytest.mark.parametrize("language", ["", "eng;rm -rf", "a"])
def test_unsafe_ocr_language_configuration_is_rejected(language: str) -> None:
    with pytest.raises(ValidationError):
        Settings(ocr_language=language)


def test_blank_admin_credential_path_is_treated_as_unconfigured() -> None:
    settings = Settings(_env_file=None, google_application_credentials="")

    assert settings.google_application_credentials is None


def test_blank_tesseract_path_is_treated_as_unconfigured() -> None:
    settings = Settings(_env_file=None, tesseract_cmd="")

    assert settings.tesseract_cmd is None


def test_blank_optional_environment_values_are_ignored(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("DAMAGE_MIN_CONFIDENCE", "")
    monkeypatch.setenv("IMAGE_SIMILARITY_HIGH_THRESHOLD", "")
    monkeypatch.setenv("IMAGE_SIMILARITY_MODERATE_THRESHOLD", "")

    settings = Settings(_env_file=None)

    assert settings.damage_min_confidence is None
    assert settings.image_similarity_high_threshold is None
    assert settings.image_similarity_moderate_threshold is None


def test_seed_password_is_not_in_settings_representation() -> None:
    settings = Settings(_env_file=None, seed_user_password="controlled-demo-password")

    assert "controlled-demo-password" not in repr(settings)


def test_tesseract_path_is_not_in_settings_representation() -> None:
    settings = Settings(_env_file=None, tesseract_cmd="C:/private/tesseract.exe")

    assert "C:/private/tesseract.exe" not in repr(settings)


def test_production_configuration_requires_every_runtime_module() -> None:
    settings = Settings(_env_file=None, app_env="production")

    with pytest.raises(RuntimeError) as error:
        settings.validate_runtime_configuration()

    message = str(error.value)
    assert "FIREBASE_PROJECT_ID" in message
    assert "GEMINI_API_KEY" in message
    assert "IMAGE_SIMILARITY_HIGH_THRESHOLD" in message
    assert "IMAGE_SIMILARITY_MODERATE_THRESHOLD" in message
    assert "DAMAGE_MIN_CONFIDENCE" in message


def test_complete_production_configuration_is_accepted() -> None:
    settings = Settings(
        _env_file=None,
        app_env="production",
        firebase_project_id="controlled-project",
        gemini_api_key="controlled-test-key",
        image_similarity_high_threshold=98.2,
        image_similarity_moderate_threshold=90.4,
        damage_min_confidence=0.74,
        baked_clip_model_id="openai/clip-vit-base-patch32",
    )

    settings.validate_runtime_configuration()


def test_production_rejects_seed_password_and_mismatched_baked_model() -> None:
    values = {
        "_env_file": None,
        "app_env": "production",
        "firebase_project_id": "controlled-project",
        "gemini_api_key": "controlled-test-key",
        "image_similarity_high_threshold": 98.2,
        "image_similarity_moderate_threshold": 90.4,
        "damage_min_confidence": 0.74,
    }
    with pytest.raises(RuntimeError, match="SEED_USER_PASSWORD"):
        Settings(
            **values,
            seed_user_password="controlled-demo-password",
        ).validate_runtime_configuration()
    with pytest.raises(RuntimeError, match="BAKED_CLIP_MODEL_ID"):
        Settings(
            **values,
            baked_clip_model_id="controlled/baked-model",
        ).validate_runtime_configuration()

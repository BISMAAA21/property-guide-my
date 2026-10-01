from unittest.mock import patch

import httpx
import pytest

from app.core.config import Settings
from app.features.health.router import readiness
from app.main import app, create_app


@pytest.mark.asyncio
async def test_application_lifespan_initializes_firebase_admin() -> None:
    settings = Settings(_env_file=None)
    application = create_app(settings)
    with patch("app.main.initialize_firebase") as initialize_firebase:
        async with application.router.lifespan_context(application):
            pass

    initialize_firebase.assert_called_once_with(settings)


def test_production_disables_interactive_api_documentation() -> None:
    settings = Settings(
        _env_file=None,
        app_env="production",
        firebase_project_id="controlled-project",
        gemini_api_key="controlled-test-key",
        image_similarity_high_threshold=98.2,
        image_similarity_moderate_threshold=90.4,
        damage_min_confidence=0.74,
    )

    application = create_app(settings)

    assert application.docs_url is None
    assert application.redoc_url is None
    assert application.openapi_url is None


@pytest.mark.asyncio
async def test_health_reports_real_scaffold_readiness() -> None:
    transport = httpx.ASGITransport(app=app)
    with patch(
        "app.features.health.router.get_settings",
        return_value=Settings(_env_file=None),
    ), patch(
        "app.features.health.router.is_vision_model_ready", return_value=False
    ), patch(
        "app.features.health.router.is_damage_model_ready", return_value=False
    ), patch("app.features.health.router.is_ocr_ready", return_value=False):
        async with httpx.AsyncClient(
            transport=transport, base_url="http://test"
        ) as client:
            response = await client.get("/health")

    assert response.status_code == 200
    assert response.headers["X-Request-ID"]
    assert response.headers["Cache-Control"] == "no-store"
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.json() == {
        "status": "degraded",
        "visionModelReady": False,
        "damageModelReady": False,
        "ocrReady": False,
        "simplifierConfigured": False,
    }


def test_health_is_ok_only_when_every_ai_module_is_ready() -> None:
    settings = Settings(gemini_api_key="controlled-test-key")
    with patch(
        "app.features.health.router.is_vision_model_ready", return_value=True
    ), patch(
        "app.features.health.router.is_damage_model_ready", return_value=True
    ), patch("app.features.health.router.is_ocr_ready", return_value=True):
        result = readiness(settings)

    assert result.status == "ok"
    assert result.vision_model_ready is True
    assert result.damage_model_ready is True
    assert result.ocr_ready is True
    assert result.simplifier_configured is True


@pytest.mark.asyncio
async def test_request_id_accepts_safe_value_and_replaces_unsafe_value() -> None:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        safe = await client.get("/health", headers={"X-Request-ID": "safe-id_123"})
        unsafe = await client.get("/health", headers={"X-Request-ID": "unsafe id"})

    assert safe.headers["X-Request-ID"] == "safe-id_123"
    assert unsafe.headers["X-Request-ID"] != "unsafe id"
    assert len(unsafe.headers["X-Request-ID"]) == 36

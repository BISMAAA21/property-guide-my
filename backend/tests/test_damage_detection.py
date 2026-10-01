import httpx
import pytest
from fastapi import status

from app.core.auth import AuthenticatedUser, require_user
from app.core.config import Settings, get_settings
from app.core.errors import ApiError
from app.features.damage_detection.models import DamageClass
from app.features.damage_detection.router import get_damage_service
from app.features.damage_detection.service import (
    DAMAGE_DISCLAIMER,
    DamageDetectionService,
    DamagePrediction,
)
from app.features.image_verification.models import ImagePayload
from app.main import create_app


class StaticClassifier:
    model_id = "controlled-damage-classifier"

    def __init__(self, damage_class: DamageClass, score: float = 0.81) -> None:
        self.prediction = DamagePrediction(damage_class, score)

    def classify(self, _image: ImagePayload) -> DamagePrediction:
        return self.prediction


class FailingClassifier:
    model_id = "failing-damage-classifier"

    def classify(self, _image: ImagePayload) -> DamagePrediction:
        raise RuntimeError("model unavailable")


def _settings(*, minimum: float = 0.4, max_bytes: int = 1024) -> Settings:
    return Settings(damage_min_confidence=minimum, max_image_bytes=max_bytes)


def _payload() -> ImagePayload:
    return ImagePayload("damage.jpg", "image/jpeg", b"jpeg")


@pytest.mark.parametrize(
    ("damage_class", "expected_wording"),
    [
        ("wall_crack", "possible wall crack"),
        ("water_or_damp_stain", "possible water or damp staining"),
        ("mold", "possible mold growth"),
        ("no_visible_damage", "No supported visible defect"),
    ],
)
def test_every_supported_class_has_conservative_mapped_guidance(
    damage_class: DamageClass,
    expected_wording: str,
) -> None:
    service = DamageDetectionService(
        settings=_settings(),
        classifier=StaticClassifier(damage_class),
    )

    result = service.detect(_payload())

    assert result.damage_class == damage_class
    assert expected_wording in result.recommendation
    assert result.bounding_box is None
    assert result.disclaimer == DAMAGE_DISCLAIMER
    assert "diagnosis" not in result.recommendation.lower()


@pytest.mark.asyncio
async def test_detect_damage_contract_is_authenticated_and_camel_case() -> None:
    application = create_app()
    application.dependency_overrides[require_user] = lambda: AuthenticatedUser(
        uid="student-one"
    )
    application.dependency_overrides[get_settings] = _settings
    application.dependency_overrides[get_damage_service] = lambda: (
        DamageDetectionService(
            settings=_settings(),
            classifier=StaticClassifier("wall_crack", 0.79456),
        )
    )
    transport = httpx.ASGITransport(app=application)

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/detect-damage",
            files={"image": ("wall.jpg", b"\xff\xd8\xffwall", "image/jpeg")},
        )

    assert response.status_code == 200
    assert response.json() == {
        "damageClass": "wall_crack",
        "modelScore": 0.7946,
        "boundingBox": None,
        "recommendation": (
            "The model noticed visual features consistent with a possible wall crack. "
            "Inspect the area closely, ask about previous repairs, and seek a qualified "
            "professional if concerned."
        ),
        "disclaimer": DAMAGE_DISCLAIMER,
        "modelId": "controlled-damage-classifier",
    }


@pytest.mark.asyncio
async def test_detect_damage_requires_authentication() -> None:
    application = create_app()
    application.dependency_overrides[get_damage_service] = lambda: (
        DamageDetectionService(
            settings=_settings(),
            classifier=StaticClassifier("mold"),
        )
    )
    transport = httpx.ASGITransport(app=application)

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/detect-damage",
            files={"image": ("wall.jpg", b"\xff\xd8\xffwall", "image/jpeg")},
        )

    assert response.status_code == 401
    assert response.json()["code"] == "AUTH_REQUIRED"


def test_unclear_image_returns_explicit_retry_guidance() -> None:
    service = DamageDetectionService(
        settings=_settings(minimum=0.6),
        classifier=StaticClassifier("mold", 0.45),
    )

    with pytest.raises(ApiError) as captured:
        service.detect(_payload())

    assert captured.value.status_code == status.HTTP_422_UNPROCESSABLE_CONTENT
    assert captured.value.code == "UNCLEAR_IMAGE"
    assert "well-lit close photo" in captured.value.message


def test_invalid_confidence_configuration_fails_before_model_loading() -> None:
    calls = 0

    def factory() -> StaticClassifier:
        nonlocal calls
        calls += 1
        return StaticClassifier("mold")

    service = DamageDetectionService(
        settings=_settings(minimum=0),
        classifier_factory=factory,
    )

    with pytest.raises(ApiError) as captured:
        service.detect(_payload())

    assert captured.value.code == "MODEL_NOT_READY"
    assert calls == 0


def test_damage_model_failure_maps_to_service_unavailable() -> None:
    service = DamageDetectionService(
        settings=_settings(),
        classifier=FailingClassifier(),
    )

    with pytest.raises(ApiError) as captured:
        service.detect(_payload())

    assert captured.value.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
    assert captured.value.code == "MODEL_NOT_READY"


@pytest.mark.asyncio
async def test_damage_upload_rejects_invalid_content_before_inference() -> None:
    application = create_app()
    application.dependency_overrides[require_user] = lambda: AuthenticatedUser(
        uid="student-one"
    )
    application.dependency_overrides[get_settings] = _settings
    application.dependency_overrides[get_damage_service] = lambda: (
        DamageDetectionService(
            settings=_settings(),
            classifier=StaticClassifier("mold"),
        )
    )
    transport = httpx.ASGITransport(app=application)

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/detect-damage",
            files={"image": ("damage.jpg", b"not-an-image", "image/jpeg")},
        )

    assert response.status_code == 415
    assert response.json()["code"] == "INVALID_FILE_TYPE"

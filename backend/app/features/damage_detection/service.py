import math
from collections.abc import Callable
from dataclasses import dataclass
from typing import Protocol

from fastapi import status

from app.core.config import Settings
from app.core.errors import ApiError
from app.features.damage_detection.models import (
    DamageClass,
    DamageDetectionResponse,
)
from app.shared.image_upload import ImagePayload

DAMAGE_DISCLAIMER = (
    "AI-assisted observation only; this does not confirm damage or replace "
    "a qualified property inspection."
)

RECOMMENDATIONS: dict[DamageClass, str] = {
    "wall_crack": (
        "The model noticed visual features consistent with a possible wall crack. "
        "Inspect the area closely, ask about previous repairs, and seek a qualified "
        "professional if concerned."
    ),
    "water_or_damp_stain": (
        "The model noticed visual features consistent with possible water or damp staining. "
        "Check for moisture or leaks and ask the agent about the cause and repairs."
    ),
    "mold": (
        "The model noticed visual features consistent with possible mold growth. "
        "Avoid touching the area, ask about moisture treatment, and seek professional advice."
    ),
    "no_visible_damage": (
        "No supported visible defect stood out in this photo. Continue the guided inspection "
        "and obtain professional advice if anything still concerns you."
    ),
}


@dataclass(frozen=True)
class DamagePrediction:
    damage_class: DamageClass
    score: float


class DamageClassifier(Protocol):
    @property
    def model_id(self) -> str: ...

    def classify(self, image: ImagePayload) -> DamagePrediction: ...


class DamageDetectionService:
    def __init__(
        self,
        *,
        settings: Settings,
        classifier: DamageClassifier | None = None,
        classifier_factory: Callable[[], DamageClassifier] | None = None,
    ) -> None:
        if (classifier is None and classifier_factory is None) or (
            classifier is not None and classifier_factory is not None
        ):
            raise ValueError("Supply exactly one damage classifier or classifier factory.")
        self._settings = settings
        self._classifier = classifier
        self._classifier_factory = classifier_factory

    def detect(self, image: ImagePayload) -> DamageDetectionResponse:
        minimum = self._settings.damage_min_confidence
        if minimum is None or not 0 < minimum <= 1:
            raise ApiError(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="MODEL_NOT_READY",
                message="The damage confidence threshold is not configured correctly.",
            )
        try:
            classifier = self._classifier or self._classifier_factory()
            prediction = classifier.classify(image)
        except ApiError:
            raise
        except Exception as error:
            raise ApiError(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="MODEL_NOT_READY",
                message="The damage-detection model is unavailable.",
            ) from error

        if (
            prediction.damage_class not in RECOMMENDATIONS
            or not math.isfinite(prediction.score)
            or not 0 <= prediction.score <= 1
        ):
            raise ApiError(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="MODEL_NOT_READY",
                message="The damage-detection model returned an invalid result.",
            )
        if prediction.score < minimum:
            raise ApiError(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                code="UNCLEAR_IMAGE",
                message=(
                    "The photo did not provide a clear supported observation. "
                    "Upload a well-lit close photo of the area."
                ),
                field_errors={"image": "The model confidence was below the reviewed threshold."},
            )

        return DamageDetectionResponse(
            damage_class=prediction.damage_class,
            model_score=round(prediction.score, 4),
            bounding_box=None,
            recommendation=RECOMMENDATIONS[prediction.damage_class],
            disclaimer=DAMAGE_DISCLAIMER,
            model_id=classifier.model_id,
        )

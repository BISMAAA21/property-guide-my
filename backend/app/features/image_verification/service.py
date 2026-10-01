import math
from collections.abc import Callable, Sequence
from typing import Literal, Protocol

from fastapi import status

from app.core.config import Settings
from app.core.errors import ApiError
from app.features.image_verification.models import (
    ImagePayload,
    ImageVerificationResponse,
)

DISCLAIMER = (
    "AI-assisted guidance only; this does not guarantee that the property "
    "or listing is genuine."
)


class VisionEncoder(Protocol):
    @property
    def model_id(self) -> str: ...

    def encode(self, images: Sequence[ImagePayload]) -> Sequence[Sequence[float]]: ...


class ImageVerificationService:
    def __init__(
        self,
        *,
        settings: Settings,
        encoder: VisionEncoder | None = None,
        encoder_factory: Callable[[], VisionEncoder] | None = None,
    ) -> None:
        if (encoder is None and encoder_factory is None) or (
            encoder is not None and encoder_factory is not None
        ):
            raise ValueError("Supply exactly one image encoder or encoder factory.")
        self._settings = settings
        self._encoder = encoder
        self._encoder_factory = encoder_factory

    def verify(
        self,
        *,
        visit_image: ImagePayload,
        listing_images: Sequence[ImagePayload],
    ) -> ImageVerificationResponse:
        if not listing_images:
            raise ApiError(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                code="LISTING_IMAGES_REQUIRED",
                message="At least one approved listing image is required.",
                field_errors={"listing_images": "Provide one or more listing images."},
            )
        if len(listing_images) > 8:
            raise ApiError(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                code="TOO_MANY_LISTING_IMAGES",
                message="Compare no more than eight listing images at once.",
                field_errors={"listing_images": "The listing image limit is eight."},
            )

        high = self._settings.image_similarity_high_threshold
        moderate = self._settings.image_similarity_moderate_threshold
        if not self._settings.image_similarity_thresholds_are_valid:
            raise ApiError(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="MODEL_NOT_READY",
                message="Image similarity thresholds have not been calibrated.",
            )
        assert high is not None and moderate is not None

        try:
            encoder = self._encoder or self._encoder_factory()
            embeddings = list(encoder.encode([visit_image, *listing_images]))
        except ApiError:
            raise
        except Exception as error:
            raise ApiError(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="MODEL_NOT_READY",
                message="The image verification model is unavailable.",
            ) from error
        if len(embeddings) != len(listing_images) + 1:
            raise ApiError(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="MODEL_NOT_READY",
                message="The image verification model returned incomplete embeddings.",
            )

        visit_embedding = embeddings[0]
        scores = [
            similarity_score(visit_embedding, listing_embedding)
            for listing_embedding in embeddings[1:]
        ]
        best_index = max(range(len(scores)), key=scores.__getitem__)
        best_score = round(scores[best_index], 1)
        if best_score >= high:
            level: Literal["high", "moderate", "low"] = "high"
            guidance = (
                "The visit image appears reasonably similar to one approved listing image. "
                "Continue checking the address, surroundings, and property details in person."
            )
            warning = None
        elif best_score >= moderate:
            level = "moderate"
            guidance = (
                "The visit image has some visual similarity to an approved listing image, "
                "but differences remain. Compare fixed features and ask the agent to explain them."
            )
            warning = None
        else:
            level = "low"
            guidance = (
                "The visit image looks visually different from the approved listing images. "
                "Pause and verify the exact unit, address, and listing details with the agent."
            )
            warning = (
                "Possible mismatch: the uploaded visit image has low visual similarity to every "
                "approved listing image."
            )

        return ImageVerificationResponse(
            similarity_score=best_score,
            similarity_level=level,
            possible_mismatch=level == "low",
            mismatch_warning=warning,
            best_listing_image_index=best_index,
            guidance=guidance,
            disclaimer=DISCLAIMER,
            model_id=encoder.model_id,
        )


def similarity_score(left: Sequence[float], right: Sequence[float]) -> float:
    if not left or len(left) != len(right):
        raise ApiError(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="MODEL_NOT_READY",
            message="The image verification model returned invalid embeddings.",
        )
    dot = sum(a * b for a, b in zip(left, right, strict=True))
    left_norm = math.sqrt(sum(value * value for value in left))
    right_norm = math.sqrt(sum(value * value for value in right))
    if left_norm == 0 or right_norm == 0:
        raise ApiError(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            code="MODEL_NOT_READY",
            message="The image verification model returned an empty embedding.",
        )
    cosine = max(-1.0, min(1.0, dot / (left_norm * right_norm)))
    return (cosine + 1.0) * 50.0

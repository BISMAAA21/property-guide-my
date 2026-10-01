from typing import Annotated

from fastapi import APIRouter, Depends, File, UploadFile
from starlette.concurrency import run_in_threadpool

from app.core.auth import AuthenticatedUser, require_student
from app.core.config import Settings, get_settings
from app.features.damage_detection.clip_classifier import ClipZeroShotDamageClassifier
from app.features.damage_detection.models import DamageDetectionResponse
from app.features.damage_detection.service import DamageDetectionService
from app.shared.image_upload import read_image_upload

router = APIRouter(tags=["damage-detection"])


def get_damage_service(
    settings: Annotated[Settings, Depends(get_settings)],
) -> DamageDetectionService:
    return DamageDetectionService(
        settings=settings,
        classifier_factory=lambda: ClipZeroShotDamageClassifier(settings),
    )


@router.post(
    "/detect-damage",
    response_model=DamageDetectionResponse,
    response_model_by_alias=True,
)
async def detect_damage(
    _user: Annotated[AuthenticatedUser, Depends(require_student)],
    settings: Annotated[Settings, Depends(get_settings)],
    service: Annotated[DamageDetectionService, Depends(get_damage_service)],
    image: Annotated[UploadFile, File()],
) -> DamageDetectionResponse:
    payload = await read_image_upload(
        image,
        field_name="image",
        max_bytes=settings.max_image_bytes,
    )
    return await run_in_threadpool(service.detect, payload)

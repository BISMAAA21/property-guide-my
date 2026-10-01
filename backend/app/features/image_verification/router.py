from typing import Annotated

from fastapi import APIRouter, Depends, File, UploadFile
from starlette.concurrency import run_in_threadpool

from app.core.auth import AuthenticatedUser, require_student
from app.core.config import Settings, get_settings
from app.features.image_verification.clip_encoder import ClipVisionEncoder
from app.features.image_verification.models import ImageVerificationResponse
from app.features.image_verification.service import ImageVerificationService
from app.features.image_verification.uploads import (
    read_image_upload,
    read_image_upload_batch,
)

router = APIRouter(tags=["image-verification"])


def get_verification_service(
    settings: Annotated[Settings, Depends(get_settings)],
) -> ImageVerificationService:
    return ImageVerificationService(
        settings=settings,
        encoder_factory=lambda: ClipVisionEncoder(settings),
    )


@router.post(
    "/verify-image",
    response_model=ImageVerificationResponse,
    response_model_by_alias=True,
)
async def verify_image(
    _user: Annotated[AuthenticatedUser, Depends(require_student)],
    settings: Annotated[Settings, Depends(get_settings)],
    service: Annotated[ImageVerificationService, Depends(get_verification_service)],
    visit_image: Annotated[UploadFile, File()],
    listing_images: Annotated[list[UploadFile], File()],
) -> ImageVerificationResponse:
    visit_payload = await read_image_upload(
        visit_image,
        field_name="visit_image",
        max_bytes=settings.max_image_bytes,
    )
    listing_payloads = await read_image_upload_batch(
        listing_images,
        field_name="listing_images",
        max_bytes=settings.max_image_bytes,
        max_files=settings.max_listing_images,
    )
    return await run_in_threadpool(
        service.verify,
        visit_image=visit_payload,
        listing_images=listing_payloads,
    )

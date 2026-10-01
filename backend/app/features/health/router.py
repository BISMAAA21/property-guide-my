from typing import Literal

from fastapi import APIRouter
from pydantic import BaseModel, ConfigDict

from app.core.config import Settings, get_settings
from app.features.agreements.extraction import is_ocr_ready
from app.features.damage_detection.clip_classifier import is_damage_model_ready
from app.features.image_verification.clip_encoder import is_vision_model_ready

router = APIRouter(tags=["health"])


def _to_camel(value: str) -> str:
    first, *rest = value.split("_")
    return first + "".join(part.capitalize() for part in rest)


class HealthResponse(BaseModel):
    model_config = ConfigDict(alias_generator=lambda value: _to_camel(value), populate_by_name=True)

    status: Literal["ok", "degraded"]
    vision_model_ready: bool
    damage_model_ready: bool
    ocr_ready: bool
    simplifier_configured: bool


def readiness(settings: Settings) -> HealthResponse:
    vision_ready = is_vision_model_ready(settings)
    damage_ready = is_damage_model_ready(settings)
    ocr_ready = is_ocr_ready(settings)
    simplifier_configured = bool(settings.gemini_api_key)
    return HealthResponse(
        status=(
            "ok"
            if vision_ready and damage_ready and ocr_ready and simplifier_configured
            else "degraded"
        ),
        vision_model_ready=vision_ready,
        damage_model_ready=damage_ready,
        ocr_ready=ocr_ready,
        simplifier_configured=simplifier_configured,
    )


@router.get("/health", response_model=HealthResponse, response_model_by_alias=True)
async def health() -> HealthResponse:
    return readiness(get_settings())

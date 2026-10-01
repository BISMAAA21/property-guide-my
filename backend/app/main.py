import re
from contextlib import asynccontextmanager
from uuid import uuid4

from fastapi import FastAPI, Request

from app.core.config import Settings, get_settings
from app.core.errors import install_error_handlers
from app.core.firebase import initialize_firebase
from app.features.agreements.extraction import is_ocr_ready
from app.features.agreements.router import router as agreement_router
from app.features.damage_detection.clip_classifier import ClipZeroShotDamageClassifier
from app.features.damage_detection.router import router as damage_detection_router
from app.features.health.router import router as health_router
from app.features.image_verification.clip_encoder import ClipVisionEncoder
from app.features.image_verification.router import router as image_verification_router

_SAFE_REQUEST_ID = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


def _request_id(candidate: str | None) -> str:
    return candidate if candidate and _SAFE_REQUEST_ID.fullmatch(candidate) else str(uuid4())


def create_app(settings: Settings | None = None) -> FastAPI:
    runtime_settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        runtime_settings.validate_runtime_configuration()
        initialize_firebase(runtime_settings)
        if runtime_settings.preload_vision_models:
            ClipVisionEncoder(runtime_settings)
            ClipZeroShotDamageClassifier(runtime_settings)
            if not is_ocr_ready(runtime_settings):
                raise RuntimeError("Production OCR dependencies are unavailable.")
        yield

    application = FastAPI(
        title="FYP Property Guidance AI API",
        version="0.1.0",
        description=(
            "Authenticated AI assistance for property verification, damage, and agreements."
        ),
        lifespan=lifespan,
        docs_url=None if runtime_settings.is_production else "/docs",
        redoc_url=None if runtime_settings.is_production else "/redoc",
        openapi_url=None if runtime_settings.is_production else "/openapi.json",
    )

    @application.middleware("http")
    async def attach_request_id(request: Request, call_next):
        request.state.request_id = _request_id(request.headers.get("X-Request-ID"))
        response = await call_next(request)
        response.headers["X-Request-ID"] = request.state.request_id
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    application.include_router(health_router)
    application.include_router(image_verification_router)
    application.include_router(damage_detection_router)
    application.include_router(agreement_router)
    install_error_handlers(application)
    return application


app = create_app()

from typing import Annotated

from fastapi import APIRouter, Depends, File, UploadFile
from starlette.concurrency import run_in_threadpool

from app.core.auth import AuthenticatedUser, require_student
from app.core.config import Settings, get_settings
from app.features.agreements.extraction import PdfAgreementExtractor
from app.features.agreements.models import AgreementSimplificationResponse
from app.features.agreements.provider import GeminiClauseSimplifier
from app.features.agreements.service import AgreementSimplificationService
from app.features.agreements.uploads import read_pdf_upload

router = APIRouter(tags=["agreement-simplification"])


def get_agreement_service(
    settings: Annotated[Settings, Depends(get_settings)],
) -> AgreementSimplificationService:
    return AgreementSimplificationService(
        settings=settings,
        extractor_factory=lambda: PdfAgreementExtractor(settings),
        simplifier_factory=lambda: GeminiClauseSimplifier(settings),
    )


@router.post(
    "/simplify-agreement",
    response_model=AgreementSimplificationResponse,
    response_model_by_alias=True,
)
async def simplify_agreement(
    _user: Annotated[AuthenticatedUser, Depends(require_student)],
    settings: Annotated[Settings, Depends(get_settings)],
    service: Annotated[AgreementSimplificationService, Depends(get_agreement_service)],
    document: Annotated[UploadFile, File()],
) -> AgreementSimplificationResponse:
    payload = await read_pdf_upload(document, max_bytes=settings.max_pdf_bytes)
    return await run_in_threadpool(service.simplify, payload)

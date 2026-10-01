from collections.abc import Callable, Sequence
from typing import Protocol

from fastapi import status

from app.core.config import Settings
from app.core.errors import ApiError
from app.features.agreements.models import (
    AgreementClause,
    AgreementSimplificationResponse,
    ExtractedAgreement,
    PdfPayload,
    SimplifiedClause,
)
from app.features.agreements.segmentation import segment_agreement

LEGAL_DISCLAIMER = (
    "This is simplified legal information, not legal advice. "
    "Verify important terms with a qualified professional."
)


class AgreementExtractor(Protocol):
    def extract(self, payload: PdfPayload) -> ExtractedAgreement: ...


class ClauseSimplifier(Protocol):
    @property
    def model_id(self) -> str: ...

    def simplify(self, clauses: Sequence[AgreementClause]) -> list[SimplifiedClause]: ...


class AgreementSimplificationService:
    def __init__(
        self,
        *,
        settings: Settings,
        extractor: AgreementExtractor | None = None,
        extractor_factory: Callable[[], AgreementExtractor] | None = None,
        simplifier: ClauseSimplifier | None = None,
        simplifier_factory: Callable[[], ClauseSimplifier] | None = None,
    ) -> None:
        if (extractor is None and extractor_factory is None) or (
            extractor is not None and extractor_factory is not None
        ):
            raise ValueError("Supply exactly one agreement extractor or extractor factory.")
        if (simplifier is None and simplifier_factory is None) or (
            simplifier is not None and simplifier_factory is not None
        ):
            raise ValueError("Supply exactly one clause simplifier or simplifier factory.")
        self._settings = settings
        self._extractor = extractor
        self._extractor_factory = extractor_factory
        self._simplifier = simplifier
        self._simplifier_factory = simplifier_factory

    def simplify(self, payload: PdfPayload) -> AgreementSimplificationResponse:
        if not self._settings.gemini_api_key and self._simplifier is None:
            raise ApiError(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="PROVIDER_UNAVAILABLE",
                message="Agreement simplification is not configured.",
            )
        try:
            extractor = self._extractor or self._extractor_factory()
            extracted = extractor.extract(payload)
        except ApiError:
            raise
        except Exception as error:
            raise ApiError(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                code="UNREADABLE_FILE",
                message="The agreement text could not be extracted.",
            ) from error
        total_characters = sum(len(page.text) for page in extracted.pages)
        if total_characters > self._settings.max_agreement_text_chars:
            raise ApiError(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                code="DOCUMENT_TOO_LONG",
                message="The extracted agreement text exceeds the supported limit.",
            )
        clauses = segment_agreement(
            extracted,
            max_clauses=self._settings.max_agreement_clauses,
        )
        try:
            simplifier = self._simplifier or self._simplifier_factory()
            output = simplifier.simplify(clauses)
        except ApiError:
            raise
        except Exception as error:
            raise ApiError(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="PROVIDER_UNAVAILABLE",
                message="The agreement provider could not simplify the clauses.",
            ) from error
        self._validate_output(clauses, output)
        return AgreementSimplificationResponse(
            extraction_method=extracted.extraction_method,
            clauses=output,
            disclaimer=LEGAL_DISCLAIMER,
            model_id=simplifier.model_id,
        )

    @staticmethod
    def _validate_output(
        input_clauses: Sequence[AgreementClause],
        output_clauses: Sequence[SimplifiedClause],
    ) -> None:
        if len(input_clauses) != len(output_clauses):
            raise _invalid_provider_output()
        for expected, returned in zip(input_clauses, output_clauses, strict=True):
            if (
                returned.id != expected.id
                or returned.title != expected.title
                or returned.original != expected.original
                or not returned.simplified.strip()
                or returned.simplified.strip() == returned.original.strip()
                or any(not point.strip() or len(point) > 300 for point in returned.important_points)
            ):
                raise _invalid_provider_output()


def _invalid_provider_output() -> ApiError:
    return ApiError(
        status_code=status.HTTP_502_BAD_GATEWAY,
        code="PROVIDER_INVALID_RESPONSE",
        message="The agreement provider changed, omitted, or invalidated clause output.",
    )

import json
from collections.abc import Sequence
from pathlib import Path
from tempfile import SpooledTemporaryFile
from typing import Any

import httpx
import pytest
from fastapi import UploadFile, status

from app.core.auth import AuthenticatedUser, require_user
from app.core.config import Settings, get_settings
from app.core.errors import ApiError
from app.features.agreements.extraction import (
    PdfAgreementExtractor,
    _resolve_tesseract_command,
)
from app.features.agreements.models import (
    AgreementClause,
    ExtractedAgreement,
    ExtractedPage,
    PdfPayload,
    SimplifiedClause,
)
from app.features.agreements.provider import GeminiClauseSimplifier
from app.features.agreements.router import get_agreement_service
from app.features.agreements.service import (
    LEGAL_DISCLAIMER,
    AgreementSimplificationService,
)
from app.features.agreements.uploads import read_pdf_upload
from app.main import create_app


class StaticExtractor:
    def __init__(self, method: str = "embedded_text") -> None:
        self.method = method

    def extract(self, _payload: PdfPayload) -> ExtractedAgreement:
        return ExtractedAgreement(
            pages=(
                ExtractedPage(
                    page_number=1,
                    text="1. Rent\nThe tenant pays RM 1,500 monthly.\n"
                    "2. Deposit\nThe deposit is RM 3,000.",
                    used_ocr=self.method != "embedded_text",
                ),
            ),
            extraction_method=self.method,  # type: ignore[arg-type]
        )


class StaticSimplifier:
    model_id = "controlled-test-simplifier"

    def simplify(self, clauses: Sequence[AgreementClause]) -> list[SimplifiedClause]:
        return [
            SimplifiedClause(
                id=clause.id,
                title=clause.title,
                original=clause.original,
                simplified=f"Plain explanation for {clause.title}.",
                important_points=["Check this term before signing."],
            )
            for clause in clauses
        ]


class InvalidSimplifier(StaticSimplifier):
    def simplify(self, clauses: Sequence[AgreementClause]) -> list[SimplifiedClause]:
        output = super().simplify(clauses)
        return list(reversed(output))


class FailingSimplifier:
    model_id = "failing-test-simplifier"

    def __init__(self, error: ApiError) -> None:
        self.error = error

    def simplify(self, _clauses: Sequence[AgreementClause]) -> list[SimplifiedClause]:
        raise self.error


def _settings(*, max_pdf_bytes: int = 1024) -> Settings:
    return Settings(
        _env_file=None,
        gemini_api_key="test-key",
        max_pdf_bytes=max_pdf_bytes,
        max_pdf_pages=30,
    )


def _service(
    *,
    method: str = "embedded_text",
    simplifier: Any | None = None,
) -> AgreementSimplificationService:
    return AgreementSimplificationService(
        settings=_settings(),
        extractor=StaticExtractor(method),
        simplifier=simplifier or StaticSimplifier(),
    )


@pytest.mark.asyncio
async def test_simplify_agreement_contract_is_authenticated_ordered_and_camel_case() -> None:
    application = create_app()
    application.dependency_overrides[require_user] = lambda: AuthenticatedUser(
        uid="student-one"
    )
    application.dependency_overrides[get_settings] = _settings
    application.dependency_overrides[get_agreement_service] = _service
    transport = httpx.ASGITransport(app=application)

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/simplify-agreement",
            files={"document": ("tenancy.pdf", b"%PDF-native", "application/pdf")},
        )

    assert response.status_code == 200
    body = response.json()
    assert body["extractionMethod"] == "embedded_text"
    assert body["modelId"] == "controlled-test-simplifier"
    assert body["disclaimer"] == LEGAL_DISCLAIMER
    assert [clause["id"] for clause in body["clauses"]] == [
        "clause-1",
        "clause-2",
    ]
    assert body["clauses"][0]["original"].startswith("1. Rent")
    assert body["clauses"][0]["importantPoints"]


@pytest.mark.asyncio
async def test_simplify_agreement_requires_authentication() -> None:
    application = create_app()
    application.dependency_overrides[get_agreement_service] = _service
    transport = httpx.ASGITransport(app=application)

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/simplify-agreement",
            files={"document": ("tenancy.pdf", b"%PDF-native", "application/pdf")},
        )

    assert response.status_code == 401
    assert response.json()["code"] == "AUTH_REQUIRED"


@pytest.mark.asyncio
async def test_simplify_agreement_rejects_non_student_role_before_processing() -> None:
    application = create_app()
    application.dependency_overrides[require_user] = lambda: AuthenticatedUser(
        uid="agent-one", role="agent"
    )
    application.dependency_overrides[get_agreement_service] = _service
    transport = httpx.ASGITransport(app=application)

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/simplify-agreement",
            files={"document": ("tenancy.pdf", b"%PDF-native", "application/pdf")},
        )

    assert response.status_code == 403
    assert response.json()["code"] == "ROLE_FORBIDDEN"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("content", "content_type", "max_bytes", "expected_status", "expected_code"),
    [
        (b"%PDF-too-large", "application/pdf", 4, 413, "FILE_TOO_LARGE"),
        (b"not-a-pdf", "application/pdf", 1024, 415, "INVALID_FILE_TYPE"),
        (b"%PDF-content", "text/plain", 1024, 415, "INVALID_FILE_TYPE"),
    ],
)
async def test_agreement_upload_rejects_invalid_documents_before_processing(
    content: bytes,
    content_type: str,
    max_bytes: int,
    expected_status: int,
    expected_code: str,
) -> None:
    settings = _settings(max_pdf_bytes=max_bytes)
    application = create_app()
    application.dependency_overrides[require_user] = lambda: AuthenticatedUser(
        uid="student-one"
    )
    application.dependency_overrides[get_settings] = lambda: settings
    application.dependency_overrides[get_agreement_service] = _service
    transport = httpx.ASGITransport(app=application)

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/simplify-agreement",
            files={"document": ("tenancy.pdf", content, content_type)},
        )

    assert response.status_code == expected_status
    assert response.json()["code"] == expected_code


@pytest.mark.asyncio
async def test_pdf_upload_reader_closes_temporary_file() -> None:
    temporary_file = SpooledTemporaryFile()  # noqa: SIM115 - closure is asserted
    temporary_file.write(b"%PDF-test")
    temporary_file.seek(0)
    upload = UploadFile(
        file=temporary_file,
        filename="tenancy.pdf",
        headers={"content-type": "application/pdf"},
    )

    payload = await read_pdf_upload(upload, max_bytes=1024)

    assert payload.filename == "tenancy.pdf"
    assert temporary_file.closed is True


def test_invalid_provider_order_is_never_returned_as_success() -> None:
    with pytest.raises(ApiError) as captured:
        _service(simplifier=InvalidSimplifier()).simplify(
            PdfPayload("tenancy.pdf", b"%PDF-test")
        )

    assert captured.value.status_code == status.HTTP_502_BAD_GATEWAY
    assert captured.value.code == "PROVIDER_INVALID_RESPONSE"


def test_provider_quota_error_is_preserved() -> None:
    quota_error = ApiError(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        code="RATE_LIMITED",
        message="Quota exhausted.",
    )
    with pytest.raises(ApiError) as captured:
        _service(simplifier=FailingSimplifier(quota_error)).simplify(
            PdfPayload("tenancy.pdf", b"%PDF-test")
        )

    assert captured.value is quota_error


class _FakeProviderClientError(Exception):
    def __init__(self, code: int) -> None:
        self.code = code


class _FakeProviderServerError(Exception):
    pass


class _FakeGenerateConfig:
    def __init__(self, **kwargs: Any) -> None:
        self.values = kwargs


class _FakeProviderTypes:
    GenerateContentConfig = _FakeGenerateConfig


class _FakeProviderModels:
    def __init__(self, response: object) -> None:
        self.response = response
        self.last_request: dict[str, Any] | None = None

    def generate_content(self, **kwargs: Any) -> object:
        self.last_request = kwargs
        if isinstance(self.response, Exception):
            raise self.response
        return self.response


class _FakeProviderClient:
    def __init__(self, response: object) -> None:
        self.models = _FakeProviderModels(response)


class _FakeProviderResponse:
    def __init__(self, text: str) -> None:
        self.text = text


def _provider(response: object) -> GeminiClauseSimplifier:
    provider = object.__new__(GeminiClauseSimplifier)
    provider._model_id = "controlled-provider"  # noqa: SLF001
    provider._batch_size = 12  # noqa: SLF001
    provider._types = _FakeProviderTypes  # noqa: SLF001
    provider._client_error = _FakeProviderClientError  # noqa: SLF001
    provider._server_error = _FakeProviderServerError  # noqa: SLF001
    provider._client = _FakeProviderClient(response)  # noqa: SLF001
    return provider


def _provider_clause() -> AgreementClause:
    return AgreementClause("clause-1", "Rent", "1. RENT\nPay monthly.")


def test_gemini_adapter_rejects_invalid_provider_json() -> None:
    with pytest.raises(ApiError) as captured:
        _provider(_FakeProviderResponse("not-json")).simplify([_provider_clause()])

    assert captured.value.status_code == status.HTTP_502_BAD_GATEWAY
    assert captured.value.code == "PROVIDER_INVALID_RESPONSE"


def test_gemini_adapter_maps_quota_response_to_rate_limited() -> None:
    with pytest.raises(ApiError) as captured:
        _provider(_FakeProviderClientError(429)).simplify([_provider_clause()])

    assert captured.value.status_code == status.HTTP_429_TOO_MANY_REQUESTS
    assert captured.value.code == "RATE_LIMITED"


@pytest.mark.parametrize("client_code", [400, 404])
def test_gemini_adapter_maps_model_rejection_to_configuration_error(
    client_code: int,
) -> None:
    with pytest.raises(ApiError) as captured:
        _provider(_FakeProviderClientError(client_code)).simplify([_provider_clause()])

    assert captured.value.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
    assert captured.value.code == "PROVIDER_CONFIGURATION_ERROR"


@pytest.mark.parametrize("client_code", [401, 403])
def test_gemini_adapter_maps_credential_rejection_to_auth_failure(
    client_code: int,
) -> None:
    with pytest.raises(ApiError) as captured:
        _provider(_FakeProviderClientError(client_code)).simplify([_provider_clause()])

    assert captured.value.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
    assert captured.value.code == "PROVIDER_AUTH_FAILED"


def test_gemini_adapter_separates_untrusted_clause_data_from_instructions() -> None:
    response = _FakeProviderResponse(
        json.dumps(
            {
                "clauses": [
                    {
                        "id": "clause-1",
                        "title": "Rent",
                        "original": "1. RENT\nPay monthly.",
                        "simplified": "You must pay each month.",
                        "importantPoints": ["Monthly payment"],
                    }
                ]
            }
        )
    )
    provider = _provider(response)

    provider.simplify([_provider_clause()])

    request = provider._client.models.last_request  # noqa: SLF001
    assert request is not None
    assert json.loads(request["contents"])["clauses"][0]["original"].startswith(
        "1. RENT"
    )
    config = request["config"]
    assert "untrusted quoted data" in config.values["system_instruction"]
    assert "untrusted quoted data" not in request["contents"]


class _FakePixmap:
    width = 1
    height = 1
    samples = b"\x00\x00\x00"


class _FakePage:
    def __init__(self, text: str) -> None:
        self.text = text

    def get_text(self, _mode: str) -> str:
        return self.text

    def get_pixmap(self, **_kwargs: Any) -> _FakePixmap:
        return _FakePixmap()


class _FakeDocument:
    def __init__(self, pages: list[_FakePage], *, needs_pass: bool = False) -> None:
        self.pages = pages
        self.needs_pass = needs_pass
        self.closed = False

    @property
    def page_count(self) -> int:
        return len(self.pages)

    def __iter__(self):
        return iter(self.pages)

    def close(self) -> None:
        self.closed = True


class _FakeFitz:
    def __init__(self, document: _FakeDocument | Exception) -> None:
        self.document = document

    def open(self, **_kwargs: Any) -> _FakeDocument:
        if isinstance(self.document, Exception):
            raise self.document
        return self.document

    @staticmethod
    def Matrix(_x: int, _y: int) -> tuple[int, int]:
        return (_x, _y)


class _FakeImage:
    @staticmethod
    def frombytes(*_args: Any) -> object:
        return object()


class _FakeTesseract:
    def __init__(self, text: str = "Scanned tenancy clause") -> None:
        self.text = text
        self.calls = 0

    def image_to_string(self, *_args: Any, **_kwargs: Any) -> str:
        self.calls += 1
        return self.text


def _extractor(
    document: _FakeDocument | Exception,
    tesseract: _FakeTesseract,
) -> PdfAgreementExtractor:
    extractor = object.__new__(PdfAgreementExtractor)
    extractor._settings = _settings()  # noqa: SLF001 - isolated dependency test
    extractor._fitz = _FakeFitz(document)  # noqa: SLF001
    extractor._pytesseract = tesseract  # noqa: SLF001
    extractor._image_type = _FakeImage  # noqa: SLF001
    return extractor


def test_native_pdf_uses_embedded_text_without_ocr() -> None:
    document = _FakeDocument([_FakePage("1. RENT " + "monthly payment " * 4)])
    tesseract = _FakeTesseract()

    result = _extractor(document, tesseract).extract(PdfPayload("native.pdf", b"pdf"))

    assert result.extraction_method == "embedded_text"
    assert tesseract.calls == 0
    assert document.closed is True


def test_explicit_tesseract_command_does_not_require_path(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    command = tmp_path / "tesseract.exe"
    command.touch()
    monkeypatch.setattr("app.features.agreements.extraction.shutil.which", lambda _: None)

    resolved = _resolve_tesseract_command(
        Settings(_env_file=None, tesseract_cmd=command)
    )

    assert resolved == str(command)


def test_missing_explicit_tesseract_command_is_not_ready(tmp_path: Path) -> None:
    resolved = _resolve_tesseract_command(
        Settings(_env_file=None, tesseract_cmd=tmp_path / "missing.exe")
    )

    assert resolved is None


def test_scanned_pdf_uses_ocr_and_closes_document(monkeypatch: pytest.MonkeyPatch) -> None:
    document = _FakeDocument([_FakePage("")])
    tesseract = _FakeTesseract("1. RENT\nThe tenant pays monthly.")
    monkeypatch.setattr("app.features.agreements.extraction.shutil.which", lambda _: "tesseract")

    result = _extractor(document, tesseract).extract(PdfPayload("scan.pdf", b"pdf"))

    assert result.extraction_method == "ocr"
    assert result.pages[0].text.startswith("1. RENT")
    assert tesseract.calls == 1
    assert document.closed is True


def test_mixed_pdf_only_ocr_processes_insufficient_pages(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    document = _FakeDocument(
        [_FakePage("1. RENT " + "monthly payment " * 4), _FakePage("")]
    )
    tesseract = _FakeTesseract("2. DEPOSIT\nThe deposit is refundable.")
    monkeypatch.setattr("app.features.agreements.extraction.shutil.which", lambda _: "tesseract")

    result = _extractor(document, tesseract).extract(PdfPayload("mixed.pdf", b"pdf"))

    assert result.extraction_method == "mixed"
    assert [page.used_ocr for page in result.pages] == [False, True]
    assert tesseract.calls == 1


@pytest.mark.parametrize(
    ("document", "expected_code"),
    [
        (_FakeDocument([_FakePage("text")], needs_pass=True), "ENCRYPTED_DOCUMENT"),
        (RuntimeError("corrupt"), "UNREADABLE_FILE"),
    ],
)
def test_encrypted_and_corrupt_pdfs_fail_explicitly(
    document: _FakeDocument | Exception,
    expected_code: str,
) -> None:
    with pytest.raises(ApiError) as captured:
        _extractor(document, _FakeTesseract()).extract(PdfPayload("bad.pdf", b"pdf"))

    assert captured.value.code == expected_code


def test_ocr_failure_is_explicit_and_document_is_closed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    document = _FakeDocument([_FakePage("")])
    monkeypatch.setattr("app.features.agreements.extraction.shutil.which", lambda _: "tesseract")

    with pytest.raises(ApiError) as captured:
        _extractor(document, _FakeTesseract("")).extract(PdfPayload("scan.pdf", b"pdf"))

    assert captured.value.code == "OCR_FAILED"
    assert document.closed is True


def test_pdf_page_limit_is_explicit_and_document_is_closed() -> None:
    document = _FakeDocument([_FakePage("page")] * 31)

    with pytest.raises(ApiError) as captured:
        _extractor(document, _FakeTesseract()).extract(
            PdfPayload("long.pdf", b"pdf")
        )

    assert captured.value.code == "PDF_PAGE_LIMIT"
    assert document.closed is True

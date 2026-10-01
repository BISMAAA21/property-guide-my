import shutil
from typing import Any

from fastapi import status

from app.core.config import Settings
from app.core.errors import ApiError
from app.features.agreements.models import (
    ExtractedAgreement,
    ExtractedPage,
    PdfPayload,
)


class PdfAgreementExtractor:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        try:
            import pymupdf as fitz
            import pytesseract
            from PIL import Image

            self._fitz = fitz
            self._pytesseract = pytesseract
            self._image_type = Image
        except Exception as error:
            raise ApiError(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="MODEL_NOT_READY",
                message="PDF extraction and OCR dependencies are unavailable.",
            ) from error

    def extract(self, payload: PdfPayload) -> ExtractedAgreement:
        document: Any | None = None
        try:
            document = self._fitz.open(stream=payload.data, filetype="pdf")
            if document.needs_pass:
                raise ApiError(
                    status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                    code="ENCRYPTED_DOCUMENT",
                    message="Password-protected PDFs are not supported.",
                )
            if document.page_count <= 0:
                raise ApiError(
                    status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                    code="UNREADABLE_FILE",
                    message="The PDF does not contain readable pages.",
                )
            if document.page_count > self._settings.max_pdf_pages:
                raise ApiError(
                    status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                    code="PDF_PAGE_LIMIT",
                    message=(
                        f"Upload an agreement with no more than "
                        f"{self._settings.max_pdf_pages} pages."
                    ),
                )

            pages: list[ExtractedPage] = []
            for index, page in enumerate(document):
                embedded = _normalize_text(page.get_text("text"))
                if _meaningful_character_count(embedded) >= (
                    self._settings.ocr_min_embedded_text_chars
                ):
                    pages.append(
                        ExtractedPage(
                            page_number=index + 1,
                            text=embedded,
                            used_ocr=False,
                        )
                    )
                    continue
                pages.append(
                    ExtractedPage(
                        page_number=index + 1,
                        text=self._ocr_page(page, index + 1),
                        used_ocr=True,
                    )
                )
        except ApiError:
            raise
        except Exception as error:
            raise ApiError(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                code="UNREADABLE_FILE",
                message="The uploaded PDF could not be opened or read.",
            ) from error
        finally:
            if document is not None:
                document.close()

        if not any(_meaningful_character_count(page.text) > 0 for page in pages):
            raise ApiError(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                code="UNREADABLE_FILE",
                message="No readable English text was found in the PDF.",
            )
        used_ocr = [page.used_ocr for page in pages]
        method = "ocr" if all(used_ocr) else "mixed" if any(used_ocr) else "embedded_text"
        return ExtractedAgreement(pages=tuple(pages), extraction_method=method)

    def _ocr_page(self, page: Any, page_number: int) -> str:
        command = _resolve_tesseract_command(self._settings)
        if command is None:
            raise ApiError(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="MODEL_NOT_READY",
                message=(
                    "Tesseract OCR is not installed or available through "
                    "TESSERACT_CMD or PATH."
                ),
            )
        try:
            if self._settings.tesseract_cmd is not None:
                self._pytesseract.pytesseract.tesseract_cmd = command
            pixmap = page.get_pixmap(matrix=self._fitz.Matrix(2, 2), alpha=False)
            image = self._image_type.frombytes(
                "RGB",
                (pixmap.width, pixmap.height),
                pixmap.samples,
            )
            text = self._pytesseract.image_to_string(
                image,
                lang=self._settings.ocr_language,
                timeout=self._settings.ocr_timeout_seconds,
            )
            normalized = _normalize_text(text)
            if _meaningful_character_count(normalized) == 0:
                raise ValueError("OCR returned no meaningful text")
            return normalized
        except ApiError:
            raise
        except Exception as error:
            raise ApiError(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                code="OCR_FAILED",
                message=f"OCR could not read page {page_number}.",
            ) from error


def is_ocr_ready(settings: Settings) -> bool:
    if _resolve_tesseract_command(settings) is None:
        return False
    try:
        import pymupdf  # noqa: F401
        import pytesseract  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError:
        return False
    return True


def _resolve_tesseract_command(settings: Settings) -> str | None:
    configured = settings.tesseract_cmd
    if configured is not None:
        resolved = configured.expanduser()
        return str(resolved) if resolved.is_file() else None
    return shutil.which("tesseract")


def _normalize_text(value: str) -> str:
    lines = [" ".join(line.split()) for line in value.replace("\x00", "").splitlines()]
    return "\n".join(line for line in lines if line).strip()


def _meaningful_character_count(value: str) -> int:
    return sum(character.isalnum() for character in value)

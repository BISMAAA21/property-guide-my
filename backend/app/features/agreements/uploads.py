from fastapi import UploadFile, status

from app.core.errors import ApiError
from app.features.agreements.models import PdfPayload


async def read_pdf_upload(
    upload: UploadFile,
    *,
    max_bytes: int,
) -> PdfPayload:
    try:
        data = await upload.read(max_bytes + 1)
    finally:
        await upload.close()
    if not data or len(data) > max_bytes:
        raise ApiError(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE,
            code="FILE_TOO_LARGE",
            message=f"Upload a PDF smaller than {max_bytes // (1024 * 1024)} MiB.",
            field_errors={"document": "The PDF is empty or exceeds the upload limit."},
        )
    claimed_type = (upload.content_type or "").lower().split(";")[0].strip()
    if claimed_type != "application/pdf" or not data.startswith(b"%PDF-"):
        raise ApiError(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            code="INVALID_FILE_TYPE",
            message="Upload an English PDF tenancy agreement.",
            field_errors={"document": "The declared type does not match PDF content."},
        )
    return PdfPayload(filename=upload.filename or "agreement.pdf", data=data)

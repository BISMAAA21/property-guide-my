from dataclasses import dataclass

from fastapi import UploadFile, status

from app.core.errors import ApiError

ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp"}


@dataclass(frozen=True)
class ImagePayload:
    filename: str
    content_type: str
    data: bytes


def detect_image_content_type(data: bytes) -> str | None:
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    return None


async def read_image_upload(
    upload: UploadFile,
    *,
    field_name: str,
    max_bytes: int,
) -> ImagePayload:
    try:
        data = await upload.read(max_bytes + 1)
    finally:
        await upload.close()

    if not data or len(data) > max_bytes:
        raise ApiError(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE,
            code="FILE_TOO_LARGE",
            message=f"Upload an image smaller than {max_bytes // (1024 * 1024)} MiB.",
            field_errors={field_name: "The image is empty or exceeds the upload limit."},
        )

    claimed_type = (upload.content_type or "").lower()
    detected_type = detect_image_content_type(data)
    if claimed_type not in ALLOWED_IMAGE_TYPES or detected_type != claimed_type:
        raise ApiError(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            code="INVALID_FILE_TYPE",
            message="Upload a JPEG, PNG, or WebP image.",
            field_errors={
                field_name: "The declared type does not match supported image content."
            },
        )

    return ImagePayload(
        filename=upload.filename or "image",
        content_type=detected_type,
        data=data,
    )


async def read_image_upload_batch(
    uploads: list[UploadFile],
    *,
    field_name: str,
    max_bytes: int,
    max_files: int,
) -> list[ImagePayload]:
    try:
        if not uploads or len(uploads) > max_files:
            raise ApiError(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                code="INVALID_IMAGE_COUNT",
                message=f"Upload between 1 and {max_files} listing images.",
                field_errors={
                    field_name: f"Choose between 1 and {max_files} listing images."
                },
            )
        return [
            await read_image_upload(
                upload,
                field_name=f"{field_name}[{index}]",
                max_bytes=max_bytes,
            )
            for index, upload in enumerate(uploads)
        ]
    finally:
        for upload in uploads:
            if not upload.file.closed:
                await upload.close()

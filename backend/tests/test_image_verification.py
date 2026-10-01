from collections.abc import Sequence
from tempfile import SpooledTemporaryFile

import httpx
import pytest
from fastapi import UploadFile, status

from app.core.auth import AuthenticatedUser, require_user
from app.core.config import Settings, get_settings
from app.core.errors import ApiError
from app.features.image_verification.models import ImagePayload
from app.features.image_verification.router import get_verification_service
from app.features.image_verification.service import ImageVerificationService
from app.features.image_verification.uploads import (
    read_image_upload,
    read_image_upload_batch,
)
from app.main import create_app


class StaticEncoder:
    model_id = "controlled-test-encoder"

    def __init__(self, embeddings: Sequence[Sequence[float]]) -> None:
        self.embeddings = embeddings

    def encode(self, _images: Sequence[ImagePayload]) -> Sequence[Sequence[float]]:
        return self.embeddings


class FailingEncoder:
    model_id = "unavailable-test-encoder"

    def encode(self, _images: Sequence[ImagePayload]) -> Sequence[Sequence[float]]:
        raise RuntimeError("model unavailable")


def _settings(*, max_image_bytes: int = 1024) -> Settings:
    return Settings(
        max_image_bytes=max_image_bytes,
        image_similarity_high_threshold=90,
        image_similarity_moderate_threshold=70,
    )


def _payload(name: str) -> ImagePayload:
    return ImagePayload(filename=name, content_type="image/jpeg", data=b"jpeg")


def test_similar_pair_ranks_above_unrelated_and_best_index_is_deterministic() -> None:
    service = ImageVerificationService(
        settings=_settings(),
        encoder=StaticEncoder(
            [
                [1.0, 0.0],
                [0.0, 1.0],
                [0.8, 0.2],
                [0.8, 0.2],
            ]
        ),
    )

    result = service.verify(
        visit_image=_payload("visit.jpg"),
        listing_images=[
            _payload("unrelated.jpg"),
            _payload("similar-first.jpg"),
            _payload("similar-tie.jpg"),
        ],
    )

    assert result.best_listing_image_index == 1
    assert result.similarity_score > 90
    assert result.similarity_level == "high"
    assert result.possible_mismatch is False
    assert "genuine" in result.disclaimer


def test_low_similarity_returns_possible_mismatch_without_fraud_verdict() -> None:
    service = ImageVerificationService(
        settings=_settings(),
        encoder=StaticEncoder([[1.0, 0.0], [-1.0, 0.0]]),
    )

    result = service.verify(
        visit_image=_payload("visit.jpg"),
        listing_images=[_payload("different.jpg")],
    )

    assert result.similarity_score == 0
    assert result.similarity_level == "low"
    assert result.possible_mismatch is True
    assert result.mismatch_warning is not None
    combined = f"{result.guidance} {result.mismatch_warning}".lower()
    assert "definitely fake" not in combined
    assert "definitely genuine" not in combined


def test_uncalibrated_thresholds_fail_explicitly() -> None:
    service = ImageVerificationService(
        settings=Settings(
            _env_file=None,
            image_similarity_high_threshold=None,
            image_similarity_moderate_threshold=None,
        ),
        encoder=StaticEncoder([[1.0], [1.0]]),
    )

    with pytest.raises(ApiError) as captured:
        service.verify(
            visit_image=_payload("visit.jpg"),
            listing_images=[_payload("listing.jpg")],
        )

    assert captured.value.code == "MODEL_NOT_READY"


@pytest.mark.asyncio
async def test_verify_image_contract_is_authenticated_and_camel_case() -> None:
    application = create_app()
    application.dependency_overrides[require_user] = lambda: AuthenticatedUser(
        uid="student-one"
    )
    application.dependency_overrides[get_settings] = _settings
    application.dependency_overrides[get_verification_service] = lambda: (
        ImageVerificationService(
            settings=_settings(),
            encoder=StaticEncoder([[1.0, 0.0], [0.9, 0.1], [0.0, 1.0]]),
        )
    )
    transport = httpx.ASGITransport(app=application)
    files = [
        ("visit_image", ("visit.jpg", b"\xff\xd8\xffvisit", "image/jpeg")),
        (
            "listing_images",
            ("listing-one.jpg", b"\xff\xd8\xfflisting-one", "image/jpeg"),
        ),
        (
            "listing_images",
            ("listing-two.jpg", b"\xff\xd8\xfflisting-two", "image/jpeg"),
        ),
    ]

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/verify-image", files=files)

    assert response.status_code == 200
    assert response.json() == {
        "similarityScore": 99.7,
        "similarityLevel": "high",
        "possibleMismatch": False,
        "mismatchWarning": None,
        "bestListingImageIndex": 0,
        "guidance": (
            "The visit image appears reasonably similar to one approved listing image. "
            "Continue checking the address, surroundings, and property details in person."
        ),
        "disclaimer": (
            "AI-assisted guidance only; this does not guarantee that the property "
            "or listing is genuine."
        ),
        "modelId": "controlled-test-encoder",
    }


@pytest.mark.asyncio
async def test_verify_image_requires_authentication() -> None:
    application = create_app()
    application.dependency_overrides[get_verification_service] = lambda: (
        ImageVerificationService(
            settings=_settings(),
            encoder=StaticEncoder([[1.0], [1.0]]),
        )
    )
    transport = httpx.ASGITransport(app=application)

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/verify-image",
            files=[
                ("visit_image", ("visit.jpg", b"\xff\xd8\xffvisit", "image/jpeg")),
                (
                    "listing_images",
                    ("listing.jpg", b"\xff\xd8\xfflisting", "image/jpeg"),
                ),
            ],
        )

    assert response.status_code == 401
    assert response.json()["code"] == "AUTH_REQUIRED"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("content", "content_type", "expected_code", "max_bytes"),
    [
        (b"\xff\xd8\xfftoo-large", "image/jpeg", "FILE_TOO_LARGE", 4),
        (b"\xff\xd8\xffjpeg", "image/png", "INVALID_FILE_TYPE", 1024),
        (b"not-an-image", "image/jpeg", "INVALID_FILE_TYPE", 1024),
    ],
)
async def test_verify_image_rejects_oversized_or_mismatched_content(
    content: bytes,
    content_type: str,
    expected_code: str,
    max_bytes: int,
) -> None:
    application = create_app()
    settings = _settings(max_image_bytes=max_bytes)
    application.dependency_overrides[require_user] = lambda: AuthenticatedUser(
        uid="student-one"
    )
    application.dependency_overrides[get_settings] = lambda: settings
    application.dependency_overrides[get_verification_service] = lambda: (
        ImageVerificationService(
            settings=settings,
            encoder=StaticEncoder([[1.0], [1.0]]),
        )
    )
    transport = httpx.ASGITransport(app=application)

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/verify-image",
            files=[
                ("visit_image", ("visit", content, content_type)),
                (
                    "listing_images",
                    ("listing.jpg", b"\xff\xd8\xfflisting", "image/jpeg"),
                ),
            ],
        )

    expected_status = 413 if expected_code == "FILE_TOO_LARGE" else 415
    assert response.status_code == expected_status
    assert response.json()["code"] == expected_code


@pytest.mark.asyncio
async def test_model_failure_maps_to_explicit_service_error() -> None:
    service = ImageVerificationService(settings=_settings(), encoder=FailingEncoder())

    with pytest.raises(ApiError) as captured:
        service.verify(
            visit_image=_payload("visit.jpg"),
            listing_images=[_payload("listing.jpg")],
        )

    assert captured.value.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
    assert captured.value.code == "MODEL_NOT_READY"


@pytest.mark.asyncio
async def test_invalid_upload_is_rejected_before_the_real_model_is_loaded() -> None:
    application = create_app()
    application.dependency_overrides[require_user] = lambda: AuthenticatedUser(
        uid="student-one"
    )
    application.dependency_overrides[get_settings] = _settings
    transport = httpx.ASGITransport(app=application)

    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/verify-image",
            files=[
                ("visit_image", ("visit.jpg", b"corrupt", "image/jpeg")),
                (
                    "listing_images",
                    ("listing.jpg", b"\xff\xd8\xfflisting", "image/jpeg"),
                ),
            ],
        )

    assert response.status_code == 415
    assert response.json()["code"] == "INVALID_FILE_TYPE"


@pytest.mark.asyncio
async def test_upload_reader_closes_temporary_file() -> None:
    temporary_file = SpooledTemporaryFile()  # noqa: SIM115 - close is the behavior under test
    temporary_file.write(b"\xff\xd8\xfftest")
    temporary_file.seek(0)
    upload = UploadFile(
        file=temporary_file,
        filename="visit.jpg",
        headers={"content-type": "image/jpeg"},
    )

    payload = await read_image_upload(
        upload,
        field_name="visit_image",
        max_bytes=1024,
    )

    assert payload.content_type == "image/jpeg"
    assert temporary_file.closed is True


@pytest.mark.asyncio
async def test_upload_batch_closes_unread_files_after_a_validation_failure() -> None:
    files = []
    uploads = []
    for index, data in enumerate(
        [b"\xff\xd8\xffvalid", b"corrupt", b"\xff\xd8\xffunread"]
    ):
        temporary_file = SpooledTemporaryFile()  # noqa: SIM115 - closure is asserted
        temporary_file.write(data)
        temporary_file.seek(0)
        files.append(temporary_file)
        uploads.append(
            UploadFile(
                file=temporary_file,
                filename=f"listing-{index}.jpg",
                headers={"content-type": "image/jpeg"},
            )
        )

    with pytest.raises(ApiError) as captured:
        await read_image_upload_batch(
            uploads,
            field_name="listing_images",
            max_bytes=1024,
            max_files=8,
        )

    assert captured.value.code == "INVALID_FILE_TYPE"
    assert all(file.closed for file in files)


@pytest.mark.asyncio
async def test_upload_batch_rejects_excess_files_and_closes_them_before_reading() -> None:
    files = []
    uploads = []
    for index in range(3):
        temporary_file = SpooledTemporaryFile()  # noqa: SIM115 - closure is asserted
        temporary_file.write(b"\xff\xd8\xffvalid")
        temporary_file.seek(0)
        files.append(temporary_file)
        uploads.append(
            UploadFile(
                file=temporary_file,
                filename=f"listing-{index}.jpg",
                headers={"content-type": "image/jpeg"},
            )
        )

    with pytest.raises(ApiError) as captured:
        await read_image_upload_batch(
            uploads,
            field_name="listing_images",
            max_bytes=1024,
            max_files=2,
        )

    assert captured.value.code == "INVALID_IMAGE_COUNT"
    assert all(file.closed for file in files)

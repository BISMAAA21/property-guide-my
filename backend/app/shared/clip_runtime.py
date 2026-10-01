from collections.abc import Sequence
from functools import lru_cache
from io import BytesIO
from typing import Any

from fastapi import status

from app.core.errors import ApiError
from app.shared.image_upload import ImagePayload


class ClipRuntime:
    def __init__(self, model_id: str) -> None:
        self.model_id = model_id
        try:
            import torch
            from PIL import Image, ImageOps, UnidentifiedImageError
            from transformers import AutoProcessor, CLIPModel

            self._torch = torch
            self._image_type = Image
            self._image_ops = ImageOps
            self._unidentified_image_error = UnidentifiedImageError
            self._processor = AutoProcessor.from_pretrained(model_id)
            self._model = CLIPModel.from_pretrained(model_id)
            self._model.eval()
        except Exception as error:
            raise ApiError(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                code="MODEL_NOT_READY",
                message="The pretrained vision model could not be loaded.",
            ) from error

    def encode_images(
        self,
        images: Sequence[ImagePayload],
    ) -> Sequence[Sequence[float]]:
        normalized = self._normalize_images(images)
        inputs = self._processor(images=normalized, return_tensors="pt")
        with self._torch.inference_mode():
            model_output = self._model.get_image_features(**inputs)
            features = _projected_image_features(model_output, self._torch)
            features = features / features.norm(p=2, dim=-1, keepdim=True)
        return features.cpu().tolist()

    def classify_image(
        self,
        image: ImagePayload,
        prompts: Sequence[str],
    ) -> Sequence[float]:
        if not prompts:
            raise ValueError("At least one zero-shot prompt is required.")
        normalized = self._normalize_images([image])
        inputs = self._processor(
            text=list(prompts),
            images=normalized,
            return_tensors="pt",
            padding=True,
        )
        with self._torch.inference_mode():
            logits = self._model(**inputs).logits_per_image[0]
            probabilities = logits.softmax(dim=0)
        return probabilities.cpu().tolist()

    def _normalize_images(
        self,
        images: Sequence[ImagePayload],
    ) -> list[Any]:
        normalized: list[Any] = []
        try:
            for payload in images:
                with self._image_type.open(BytesIO(payload.data)) as image:
                    normalized.append(
                        self._image_ops.exif_transpose(image).convert("RGB").copy()
                    )
        except (self._unidentified_image_error, OSError, ValueError) as error:
            raise ApiError(
                status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
                code="UNREADABLE_FILE",
                message="One or more uploaded images could not be decoded.",
            ) from error
        return normalized


@lru_cache
def get_clip_runtime(model_id: str) -> ClipRuntime:
    return ClipRuntime(model_id)


def _projected_image_features(model_output: Any, torch: Any) -> Any:
    if torch.is_tensor(model_output):
        return model_output
    features = getattr(model_output, "pooler_output", None)
    if torch.is_tensor(features):
        return features
    raise ApiError(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        code="MODEL_NOT_READY",
        message="The pretrained vision model returned unsupported image features.",
    )

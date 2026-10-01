from collections.abc import Sequence

from app.core.config import Settings
from app.features.image_verification.models import ImagePayload
from app.shared.clip_runtime import ClipRuntime, get_clip_runtime

_loaded_model_ids: set[str] = set()


class ClipVisionEncoder:
    def __init__(self, settings: Settings) -> None:
        self._model_id = settings.vision_model_id
        self._runtime: ClipRuntime = get_clip_runtime(self._model_id)
        _loaded_model_ids.add(self._model_id)

    @property
    def model_id(self) -> str:
        return self._model_id

    def encode(self, images: Sequence[ImagePayload]) -> Sequence[Sequence[float]]:
        return self._runtime.encode_images(images)


def is_vision_model_ready(settings: Settings) -> bool:
    return (
        settings.vision_model_id in _loaded_model_ids
        and settings.image_similarity_thresholds_are_valid
    )

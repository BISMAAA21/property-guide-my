from app.core.config import Settings
from app.features.damage_detection.models import DamageClass
from app.features.damage_detection.service import DamagePrediction
from app.shared.clip_runtime import ClipRuntime, get_clip_runtime
from app.shared.image_upload import ImagePayload

_loaded_model_ids: set[str] = set()

_LABEL_PROMPTS: tuple[tuple[DamageClass, str], ...] = (
    (
        "wall_crack",
        "a close property inspection photo showing a visible crack in a wall or ceiling",
    ),
    (
        "water_or_damp_stain",
        "a close property inspection photo showing a water stain or damp patch",
    ),
    (
        "mold",
        "a close property inspection photo showing visible mold growth on an indoor surface",
    ),
    (
        "no_visible_damage",
        "a property interior surface with no visible crack, damp stain, or mold",
    ),
)


class ClipZeroShotDamageClassifier:
    def __init__(self, settings: Settings) -> None:
        self._model_id = settings.damage_model_id
        self._runtime: ClipRuntime = get_clip_runtime(self._model_id)
        _loaded_model_ids.add(self._model_id)

    @property
    def model_id(self) -> str:
        return self._model_id

    def classify(self, image: ImagePayload) -> DamagePrediction:
        scores = list(
            self._runtime.classify_image(
                image,
                [prompt for _, prompt in _LABEL_PROMPTS],
            )
        )
        if len(scores) != len(_LABEL_PROMPTS):
            raise ValueError("The zero-shot model returned incomplete label scores.")
        best_index = max(range(len(scores)), key=scores.__getitem__)
        return DamagePrediction(
            damage_class=_LABEL_PROMPTS[best_index][0],
            score=scores[best_index],
        )


def is_damage_model_ready(settings: Settings) -> bool:
    minimum = settings.damage_min_confidence
    return (
        settings.damage_model_id in _loaded_model_ids
        and minimum is not None
        and 0 < minimum <= 1
    )

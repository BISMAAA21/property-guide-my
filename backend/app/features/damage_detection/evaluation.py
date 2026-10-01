from dataclasses import dataclass

from app.features.damage_detection.models import DamageClass

SUPPORTED_CLASSES: tuple[DamageClass, ...] = (
    "wall_crack",
    "water_or_damp_stain",
    "mold",
    "no_visible_damage",
)


@dataclass(frozen=True)
class DamageEvaluationObservation:
    expected: DamageClass
    predicted: DamageClass | None
    score: float


def summarize_evaluation(
    observations: list[DamageEvaluationObservation],
) -> dict[str, object]:
    represented = {item.expected for item in observations}
    if represented != set(SUPPORTED_CLASSES):
        raise ValueError("The evidence set must represent every supported damage class.")
    per_class: dict[str, dict[str, int]] = {}
    total_correct = 0
    for damage_class in SUPPORTED_CLASSES:
        relevant = [item for item in observations if item.expected == damage_class]
        correct = sum(item.predicted == damage_class for item in relevant)
        total_correct += correct
        per_class[damage_class] = {
            "examples": len(relevant),
            "correct": correct,
        }
    demonstrable = all(item["correct"] > 0 for item in per_class.values())
    return {
        "exampleCount": len(observations),
        "correctCount": total_correct,
        "accuracy": round(total_correct / len(observations), 4),
        "perClass": per_class,
        "everyClassDemonstrated": demonstrable,
        "fineTuningFallbackRecommended": not demonstrable,
    }

import pytest

from app.features.damage_detection.evaluation import (
    DamageEvaluationObservation,
    summarize_evaluation,
)


def test_evaluation_requires_and_reports_every_supported_class() -> None:
    summary = summarize_evaluation(
        [
            DamageEvaluationObservation("wall_crack", "wall_crack", 0.8),
            DamageEvaluationObservation(
                "water_or_damp_stain",
                "water_or_damp_stain",
                0.7,
            ),
            DamageEvaluationObservation("mold", "mold", 0.75),
            DamageEvaluationObservation(
                "no_visible_damage",
                "no_visible_damage",
                0.65,
            ),
        ]
    )

    assert summary["accuracy"] == 1
    assert summary["everyClassDemonstrated"] is True
    assert summary["fineTuningFallbackRecommended"] is False


def test_evaluation_recommends_fallback_when_one_class_is_not_demonstrable() -> None:
    summary = summarize_evaluation(
        [
            DamageEvaluationObservation("wall_crack", "mold", 0.6),
            DamageEvaluationObservation(
                "water_or_damp_stain",
                "water_or_damp_stain",
                0.7,
            ),
            DamageEvaluationObservation("mold", "mold", 0.8),
            DamageEvaluationObservation(
                "no_visible_damage",
                "no_visible_damage",
                0.7,
            ),
        ]
    )

    assert summary["everyClassDemonstrated"] is False
    assert summary["fineTuningFallbackRecommended"] is True


def test_evaluation_rejects_an_incomplete_scope() -> None:
    with pytest.raises(ValueError, match="every supported damage class"):
        summarize_evaluation(
            [DamageEvaluationObservation("wall_crack", "wall_crack", 0.8)]
        )

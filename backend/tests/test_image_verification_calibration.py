import pytest

from app.features.image_verification.calibration import (
    CalibrationObservation,
    select_thresholds,
)


def test_controlled_levels_produce_deterministic_separated_thresholds() -> None:
    result = select_thresholds(
        [
            CalibrationObservation(95, "high"),
            CalibrationObservation(93, "high"),
            CalibrationObservation(78, "moderate"),
            CalibrationObservation(75, "moderate"),
            CalibrationObservation(40, "low"),
            CalibrationObservation(30, "low"),
        ]
    )

    assert result.high_threshold == 85.5
    assert result.moderate_threshold == 57.5
    assert result.macro_accuracy == 1
    assert result.correct_count == 6


def test_calibration_requires_every_output_level() -> None:
    with pytest.raises(ValueError, match="high, moderate, and low"):
        select_thresholds(
            [
                CalibrationObservation(95, "high"),
                CalibrationObservation(20, "low"),
            ]
        )

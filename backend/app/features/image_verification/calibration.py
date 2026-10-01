from dataclasses import dataclass
from typing import Literal

ExpectedLevel = Literal["high", "moderate", "low"]


@dataclass(frozen=True)
class CalibrationObservation:
    score: float
    expected_level: ExpectedLevel


@dataclass(frozen=True)
class CalibrationResult:
    high_threshold: float
    moderate_threshold: float
    macro_accuracy: float
    correct_count: int
    observation_count: int


def select_thresholds(
    observations: list[CalibrationObservation],
) -> CalibrationResult:
    if not observations or {item.expected_level for item in observations} != {
        "high",
        "moderate",
        "low",
    }:
        raise ValueError("Calibration requires high, moderate, and low observations.")
    if any(not 0 <= item.score <= 100 for item in observations):
        raise ValueError("Calibration scores must be between zero and 100.")

    scores = sorted({item.score for item in observations})
    candidates = {0.0, 100.0, *scores}
    candidates.update(
        (left + right) / 2 for left, right in zip(scores, scores[1:], strict=False)
    )
    counts = {
        level: sum(item.expected_level == level for item in observations)
        for level in ("high", "moderate", "low")
    }
    best: tuple[float, float, float, float, int] | None = None
    for moderate in candidates:
        for high in candidates:
            if not 0 <= moderate < high <= 100:
                continue
            correct_by_level = {"high": 0, "moderate": 0, "low": 0}
            correct = 0
            for item in observations:
                predicted = _classify(item.score, high=high, moderate=moderate)
                if predicted == item.expected_level:
                    correct_by_level[item.expected_level] += 1
                    correct += 1
            macro_accuracy = sum(
                correct_by_level[level] / counts[level]
                for level in ("high", "moderate", "low")
            ) / 3
            margin = min(
                min(abs(item.score - high), abs(item.score - moderate))
                for item in observations
            )
            candidate = (macro_accuracy, margin, moderate, high, correct)
            if best is None or candidate > best:
                best = candidate

    if best is None:
        raise ValueError("No valid pair of calibration thresholds was found.")
    macro_accuracy, _, moderate, high, correct = best
    return CalibrationResult(
        high_threshold=round(high, 1),
        moderate_threshold=round(moderate, 1),
        macro_accuracy=round(macro_accuracy, 4),
        correct_count=correct,
        observation_count=len(observations),
    )


def _classify(score: float, *, high: float, moderate: float) -> ExpectedLevel:
    if score >= high:
        return "high"
    if score >= moderate:
        return "moderate"
    return "low"

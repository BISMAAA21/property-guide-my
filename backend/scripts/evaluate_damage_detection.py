import argparse
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from app.core.config import Settings
from app.features.damage_detection.clip_classifier import (
    ClipZeroShotDamageClassifier,
)
from app.features.damage_detection.evaluation import (
    SUPPORTED_CLASSES,
    DamageEvaluationObservation,
    summarize_evaluation,
)
from app.shared.image_upload import ImagePayload, detect_image_content_type


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Evaluate the four-class damage baseline on controlled photos."
    )
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def _load_manifest(path: Path) -> dict[str, Any]:
    try:
        content = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"The damage evidence manifest could not be read: {error}") from error
    if not isinstance(content, dict):
        raise ValueError("The damage evidence manifest must contain a JSON object.")
    return content


def _image_payload(root: Path, relative_path: object) -> ImagePayload:
    if not isinstance(relative_path, str) or not relative_path.strip():
        raise ValueError("Every evidence image path must be a non-empty string.")
    path = (root / relative_path).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError as error:
        raise ValueError("Evidence image paths must remain inside the manifest folder.") from error
    try:
        data = path.read_bytes()
    except OSError as error:
        raise ValueError(f"Evidence image is unavailable: {relative_path}") from error
    content_type = detect_image_content_type(data)
    if content_type is None:
        raise ValueError(f"Evidence image is not JPEG, PNG, or WebP: {relative_path}")
    return ImagePayload(path.name, content_type, data)


def run(manifest_path: Path) -> dict[str, Any]:
    manifest_path = manifest_path.resolve()
    manifest = _load_manifest(manifest_path)
    model_id = manifest.get("modelId")
    minimum = manifest.get("minimumConfidence")
    examples = manifest.get("examples")
    if not isinstance(model_id, str) or not model_id.strip():
        raise ValueError("The damage evidence manifest requires modelId.")
    if not isinstance(minimum, (int, float)) or not 0 < minimum <= 1:
        raise ValueError("minimumConfidence must be greater than zero and at most one.")
    if not isinstance(examples, list) or not examples:
        raise ValueError("The damage evidence manifest requires examples.")

    settings = Settings(
        damage_model_id=model_id.strip(),
        damage_min_confidence=float(minimum),
    )
    classifier = ClipZeroShotDamageClassifier(settings)
    observations: list[DamageEvaluationObservation] = []
    recorded: list[dict[str, Any]] = []
    for index, example in enumerate(examples):
        if not isinstance(example, dict):
            raise ValueError(f"Evidence example {index + 1} must be an object.")
        expected = example.get("expectedClass")
        source = example.get("source")
        license_name = example.get("license")
        if expected not in SUPPORTED_CLASSES:
            raise ValueError(f"Evidence example {index + 1} has an unsupported class.")
        if (
            not isinstance(source, str)
            or not source.strip()
            or source.strip().lower().startswith("record ")
        ):
            raise ValueError(f"Evidence example {index + 1} requires a source attribution.")
        if (
            not isinstance(license_name, str)
            or not license_name.strip()
            or license_name.strip().lower().startswith("record ")
        ):
            raise ValueError(f"Evidence example {index + 1} requires license information.")
        payload = _image_payload(manifest_path.parent, example.get("image"))
        prediction = classifier.classify(payload)
        accepted = prediction.score >= minimum
        predicted = prediction.damage_class if accepted else None
        observations.append(
            DamageEvaluationObservation(
                expected=expected,
                predicted=predicted,
                score=prediction.score,
            )
        )
        recorded.append(
            {
                **example,
                "predictedClass": predicted,
                "modelScore": round(prediction.score, 4),
                "accepted": accepted,
            }
        )

    return {
        "generatedAt": datetime.now(UTC).isoformat(),
        "modelId": model_id.strip(),
        "minimumConfidence": minimum,
        "summary": summarize_evaluation(observations),
        "examples": recorded,
    }


def main() -> None:
    arguments = _arguments()
    try:
        report = run(arguments.manifest)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    serialized = json.dumps(report, indent=2)
    if arguments.output is None:
        print(serialized)
        return
    arguments.output.write_text(f"{serialized}\n", encoding="utf-8")
    print(f"Damage evaluation report written to {arguments.output}")


if __name__ == "__main__":
    main()

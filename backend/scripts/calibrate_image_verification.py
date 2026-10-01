import argparse
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from app.core.config import Settings
from app.features.image_verification.calibration import (
    CalibrationObservation,
    select_thresholds,
)
from app.features.image_verification.clip_encoder import ClipVisionEncoder
from app.features.image_verification.models import ImagePayload
from app.features.image_verification.service import similarity_score
from app.features.image_verification.uploads import detect_image_content_type


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Calibrate image-similarity thresholds from controlled image pairs."
    )
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def _load_manifest(path: Path) -> dict[str, Any]:
    try:
        content = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"The calibration manifest could not be read: {error}") from error
    if not isinstance(content, dict):
        raise ValueError("The calibration manifest must contain a JSON object.")
    return content


def _image_payload(root: Path, relative_path: object) -> ImagePayload:
    if not isinstance(relative_path, str) or not relative_path.strip():
        raise ValueError("Every calibration image path must be a non-empty string.")
    path = (root / relative_path).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError as error:
        raise ValueError(
            "Calibration image paths must remain inside the manifest folder."
        ) from error
    try:
        data = path.read_bytes()
    except OSError as error:
        raise ValueError(f"Calibration image is unavailable: {relative_path}") from error
    content_type = detect_image_content_type(data)
    if content_type is None:
        raise ValueError(f"Calibration image is not JPEG, PNG, or WebP: {relative_path}")
    return ImagePayload(filename=path.name, content_type=content_type, data=data)


def run(manifest_path: Path) -> dict[str, Any]:
    manifest_path = manifest_path.resolve()
    manifest = _load_manifest(manifest_path)
    model_id = manifest.get("modelId")
    pairs = manifest.get("pairs")
    if not isinstance(model_id, str) or not model_id.strip():
        raise ValueError("The calibration manifest requires modelId.")
    if not isinstance(pairs, list) or not pairs:
        raise ValueError("The calibration manifest requires at least one image pair.")

    encoder = ClipVisionEncoder(Settings(vision_model_id=model_id.strip()))
    observations: list[CalibrationObservation] = []
    recorded_pairs: list[dict[str, Any]] = []
    for index, pair in enumerate(pairs):
        if not isinstance(pair, dict):
            raise ValueError(f"Calibration pair {index + 1} must be an object.")
        expected = pair.get("expectedLevel")
        if expected not in {"high", "moderate", "low"}:
            raise ValueError(
                f"Calibration pair {index + 1} requires high, moderate, or low expectedLevel."
            )
        visit = _image_payload(manifest_path.parent, pair.get("visitImage"))
        listing = _image_payload(manifest_path.parent, pair.get("listingImage"))
        embeddings = encoder.encode([visit, listing])
        score = round(similarity_score(embeddings[0], embeddings[1]), 1)
        observations.append(CalibrationObservation(score=score, expected_level=expected))
        recorded_pairs.append(
            {
                "visitImage": pair["visitImage"],
                "listingImage": pair["listingImage"],
                "expectedLevel": expected,
                "score": score,
            }
        )

    result = select_thresholds(observations)
    return {
        "generatedAt": datetime.now(UTC).isoformat(),
        "modelId": model_id.strip(),
        "pairCount": len(recorded_pairs),
        "pairs": recorded_pairs,
        "recommendedThresholds": {
            "IMAGE_SIMILARITY_HIGH_THRESHOLD": result.high_threshold,
            "IMAGE_SIMILARITY_MODERATE_THRESHOLD": result.moderate_threshold,
        },
        "controlledSetMacroAccuracy": result.macro_accuracy,
        "correctPairs": result.correct_count,
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
    print(f"Calibration report written to {arguments.output}")


if __name__ == "__main__":
    main()

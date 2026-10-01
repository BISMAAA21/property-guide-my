import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from app.core.config import Settings
from app.core.errors import ApiError
from app.features.agreements.extraction import PdfAgreementExtractor
from app.features.agreements.models import PdfPayload
from app.features.agreements.provider import GeminiClauseSimplifier
from app.features.agreements.service import (
    LEGAL_DISCLAIMER,
    AgreementSimplificationService,
)


def _arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Evaluate controlled native/scanned agreements without logging clause text."
        )
    )
    parser.add_argument(
        "--documents-dir",
        type=Path,
        default=Path("calibration/agreements/documents"),
    )
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def _evaluate(path: Path, service: AgreementSimplificationService) -> dict[str, Any]:
    data = path.read_bytes()
    result = service.simplify(PdfPayload(path.name, data))
    return {
        "sample": path.name,
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest().upper(),
        "extractionMethod": result.extraction_method,
        "clauseCount": len(result.clauses),
        "clauseIds": [clause.id for clause in result.clauses],
        "clauseTitles": [clause.title for clause in result.clauses],
        "simplifiedChanged": all(
            clause.simplified.strip() != clause.original.strip()
            for clause in result.clauses
        ),
        "importantPointCounts": [
            len(clause.important_points) for clause in result.clauses
        ],
        "disclaimerValid": result.disclaimer == LEGAL_DISCLAIMER,
        "modelId": result.model_id,
    }


def run(documents_dir: Path) -> dict[str, Any]:
    settings = Settings()
    if not settings.gemini_api_key:
        raise ValueError("GEMINI_API_KEY is not configured in the ignored environment.")
    service = AgreementSimplificationService(
        settings=settings,
        extractor_factory=lambda: PdfAgreementExtractor(settings),
        simplifier_factory=lambda: GeminiClauseSimplifier(settings),
    )
    resolved = documents_dir.resolve()
    samples = [resolved / "native-text.pdf", resolved / "scanned.pdf"]
    missing = [path.name for path in samples if not path.is_file()]
    if missing:
        raise FileNotFoundError(
            f"Missing controlled agreement samples: {', '.join(missing)}"
        )
    return {
        "controlledData": True,
        "containsClauseText": False,
        "samples": [_evaluate(path, service) for path in samples],
    }


def main() -> None:
    args = _arguments()
    try:
        report = run(args.documents_dir)
        rendered = json.dumps(report, indent=2)
        if args.output is not None:
            output = args.output.resolve()
            if not output.name.endswith(".local.json"):
                raise ValueError("Evidence output must end with .local.json.")
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(f"{rendered}\n", encoding="utf-8")
        print(rendered)
    except ApiError as error:
        print(f"Provider run failed: {error.code}: {error.message}", file=sys.stderr)
        raise SystemExit(1) from None
    except (OSError, ValueError) as error:
        print(f"Controlled agreement evaluation failed: {error}", file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()

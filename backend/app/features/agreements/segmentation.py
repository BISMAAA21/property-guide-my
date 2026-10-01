import re

from fastapi import status

from app.core.errors import ApiError
from app.features.agreements.models import AgreementClause, ExtractedAgreement

_NUMBERED_START = re.compile(r"^(?:clause\s+)?\d+(?:\.\d+)*(?:[.)])?\s+", re.IGNORECASE)
_UPPER_HEADING = re.compile(r"^[A-Z][A-Z\s/&(),'-]{3,80}:?$")


def segment_agreement(
    agreement: ExtractedAgreement,
    *,
    max_clauses: int,
) -> list[AgreementClause]:
    normalized_pages = [
        [
            normalized
            for line in page.text.splitlines()
            if (normalized := " ".join(line.split()).strip())
        ]
        for page in agreement.pages
    ]
    has_explicit_boundaries = any(
        _is_clause_start(line) for lines in normalized_pages for line in lines
    )
    blocks: list[str] = []
    current: list[str] = []
    for lines in normalized_pages:
        for normalized in lines:
            if _is_clause_start(normalized) and current:
                blocks.append("\n".join(current))
                current = []
            current.append(normalized)
        # A document without explicit headings still needs useful, ordered chunks.
        # Page boundaries are the least destructive fallback in that case. When
        # headings exist, keep the current clause open across page boundaries.
        if current and not has_explicit_boundaries:
            blocks.append("\n".join(current))
            current = []
    if current:
        blocks.append("\n".join(current))

    clauses = [
        AgreementClause(
            id=f"clause-{index + 1}",
            title=_title_for(block, index + 1),
            original=block,
        )
        for index, block in enumerate(blocks)
        if block.strip()
    ]
    if not clauses:
        raise ApiError(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="UNREADABLE_FILE",
            message="No tenancy clauses could be identified in the PDF.",
        )
    if len(clauses) > max_clauses:
        raise ApiError(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            code="TOO_MANY_CLAUSES",
            message=f"The agreement contains more than {max_clauses} supported clauses.",
        )
    return clauses


def _is_clause_start(value: str) -> bool:
    return bool(_NUMBERED_START.match(value) or _UPPER_HEADING.fullmatch(value))


def _title_for(block: str, index: int) -> str:
    first_line = block.splitlines()[0]
    without_number = _NUMBERED_START.sub("", first_line).strip(" :-")
    if not without_number:
        return f"Clause {index}"
    words = without_number.split()
    shortened = " ".join(words[:10])
    return shortened if len(shortened) <= 100 else f"{shortened[:97]}..."

import pytest

from app.core.errors import ApiError
from app.features.agreements.models import ExtractedAgreement, ExtractedPage
from app.features.agreements.segmentation import segment_agreement


def _agreement(*pages: str) -> ExtractedAgreement:
    return ExtractedAgreement(
        pages=tuple(
            ExtractedPage(page_number=index + 1, text=text, used_ocr=False)
            for index, text in enumerate(pages)
        ),
        extraction_method="embedded_text",
    )


def test_numbered_clauses_keep_order_and_original_wording_across_pages() -> None:
    agreement = _agreement(
        "1. Rent\nThe tenant pays RM 1,500 monthly.",
        "Payment is due on the first day.\n2. Deposit\nThe deposit is RM 3,000.",
    )

    clauses = segment_agreement(agreement, max_clauses=10)

    assert [clause.id for clause in clauses] == ["clause-1", "clause-2"]
    assert clauses[0].title == "Rent"
    assert clauses[0].original == (
        "1. Rent\nThe tenant pays RM 1,500 monthly.\n"
        "Payment is due on the first day."
    )
    assert clauses[1].original == "2. Deposit\nThe deposit is RM 3,000."


def test_unheaded_document_uses_pages_as_ordered_fallback_chunks() -> None:
    clauses = segment_agreement(
        _agreement("Rent is due monthly.", "The tenant keeps the unit clean."),
        max_clauses=10,
    )

    assert [clause.original for clause in clauses] == [
        "Rent is due monthly.",
        "The tenant keeps the unit clean.",
    ]


def test_clause_limit_is_explicit() -> None:
    with pytest.raises(ApiError) as captured:
        segment_agreement(_agreement("1. Rent\n2. Deposit"), max_clauses=1)

    assert captured.value.code == "TOO_MANY_CLAUSES"

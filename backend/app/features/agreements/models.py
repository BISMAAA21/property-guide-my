from dataclasses import dataclass
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

ExtractionMethod = Literal["embedded_text", "ocr", "mixed"]


def _to_camel(value: str) -> str:
    first, *rest = value.split("_")
    return first + "".join(part.capitalize() for part in rest)


@dataclass(frozen=True)
class PdfPayload:
    filename: str
    data: bytes


@dataclass(frozen=True)
class ExtractedPage:
    page_number: int
    text: str
    used_ocr: bool


@dataclass(frozen=True)
class ExtractedAgreement:
    pages: tuple[ExtractedPage, ...]
    extraction_method: ExtractionMethod


@dataclass(frozen=True)
class AgreementClause:
    id: str
    title: str
    original: str


class SimplifiedClause(BaseModel):
    model_config = ConfigDict(alias_generator=_to_camel, populate_by_name=True)

    id: str
    title: str
    original: str
    simplified: str
    important_points: list[str] = Field(min_length=1, max_length=5)


class AgreementSimplificationResponse(BaseModel):
    model_config = ConfigDict(alias_generator=_to_camel, populate_by_name=True)

    extraction_method: ExtractionMethod
    clauses: list[SimplifiedClause] = Field(min_length=1)
    disclaimer: str
    model_id: str

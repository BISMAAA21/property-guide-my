from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from app.shared.image_upload import ImagePayload

__all__ = ["ImagePayload", "ImageVerificationResponse"]


def _to_camel(value: str) -> str:
    first, *rest = value.split("_")
    return first + "".join(part.capitalize() for part in rest)


class ImageVerificationResponse(BaseModel):
    model_config = ConfigDict(alias_generator=_to_camel, populate_by_name=True)

    similarity_score: float = Field(ge=0, le=100)
    similarity_level: Literal["high", "moderate", "low"]
    possible_mismatch: bool
    mismatch_warning: str | None
    best_listing_image_index: int = Field(ge=0)
    guidance: str
    disclaimer: str
    model_id: str

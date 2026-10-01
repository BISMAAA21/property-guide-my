from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

DamageClass = Literal[
    "wall_crack",
    "water_or_damp_stain",
    "mold",
    "no_visible_damage",
]


def _to_camel(value: str) -> str:
    first, *rest = value.split("_")
    return first + "".join(part.capitalize() for part in rest)


class BoundingBox(BaseModel):
    model_config = ConfigDict(alias_generator=_to_camel, populate_by_name=True)

    x: float = Field(ge=0, le=1)
    y: float = Field(ge=0, le=1)
    width: float = Field(gt=0, le=1)
    height: float = Field(gt=0, le=1)


class DamageDetectionResponse(BaseModel):
    model_config = ConfigDict(alias_generator=_to_camel, populate_by_name=True)

    damage_class: DamageClass
    model_score: float = Field(ge=0, le=1)
    bounding_box: BoundingBox | None
    recommendation: str
    disclaimer: str
    model_id: str

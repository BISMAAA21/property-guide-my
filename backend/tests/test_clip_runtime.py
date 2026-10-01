from types import SimpleNamespace

import pytest

from app.core.errors import ApiError
from app.shared.clip_runtime import _projected_image_features


class _Tensor:
    pass


class _Torch:
    @staticmethod
    def is_tensor(value: object) -> bool:
        return isinstance(value, _Tensor)


def test_projected_image_features_accepts_legacy_tensor_output() -> None:
    features = _Tensor()

    assert _projected_image_features(features, _Torch()) is features


def test_projected_image_features_accepts_transformers_v5_output() -> None:
    features = _Tensor()
    output = SimpleNamespace(pooler_output=features)

    assert _projected_image_features(output, _Torch()) is features


def test_projected_image_features_rejects_unknown_output() -> None:
    with pytest.raises(ApiError) as error:
        _projected_image_features(SimpleNamespace(), _Torch())

    assert error.value.code == "MODEL_NOT_READY"

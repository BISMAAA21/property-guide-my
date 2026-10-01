import json

import pytest

from scripts.seed_demo_properties import DATASET_PATH, load_dataset


def test_controlled_property_dataset_is_valid_and_malaysia_oriented() -> None:
    records = load_dataset(DATASET_PATH)

    assert len(records) >= 5
    assert {record["propertyType"] for record in records} == {
        "room",
        "studio",
        "apartment",
        "condominium",
        "house",
    }
    assert all(record["approvalStatus"] == "draft" for record in records)
    assert all(record["imageUrls"] == [] for record in records)


def test_dataset_rejects_duplicate_identifiers(tmp_path) -> None:
    record = load_dataset(DATASET_PATH)[0]
    path = tmp_path / "duplicates.json"
    path.write_text(json.dumps([record, record]), encoding="utf-8")

    with pytest.raises(ValueError, match="unique demoId"):
        load_dataset(path)

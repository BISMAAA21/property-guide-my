"""Seed the controlled Malaysia-oriented property demonstration dataset."""

import argparse
import json
from pathlib import Path
from typing import Any

from firebase_admin import firestore

from scripts.seed_demo_user import initialize

DATASET_PATH = Path(__file__).parents[2] / "firebase" / "demo-data" / "properties.json"
PROPERTY_TYPES = frozenset({"room", "studio", "apartment", "condominium", "house"})


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Seed controlled property drafts for an existing Firebase agent."
    )
    parser.add_argument("--agent-id", required=True)
    parser.add_argument("--project-id", required=True)
    parser.add_argument("--dataset", type=Path, default=DATASET_PATH)
    return parser.parse_args()


def load_dataset(path: Path) -> list[dict[str, Any]]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, list) or not raw:
        raise ValueError("The property dataset must be a non-empty JSON array.")
    records = [validate_record(record) for record in raw]
    identifiers = [record["demoId"] for record in records]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("Every demonstration property must have a unique demoId.")
    return records


def validate_record(record: Any) -> dict[str, Any]:
    if not isinstance(record, dict):
        raise ValueError("Every property record must be a JSON object.")
    required_strings = (
        "demoId",
        "propertyName",
        "location",
        "normalizedLocation",
        "description",
        "propertyType",
        "approvalStatus",
    )
    if any(
        not isinstance(record.get(field), str) or not record[field].strip()
        for field in required_strings
    ):
        raise ValueError("A property record is missing a required text field.")
    if record["propertyType"] not in PROPERTY_TYPES:
        raise ValueError(f"Unsupported property type: {record['propertyType']}")
    if record["approvalStatus"] != "draft":
        raise ValueError("Controlled properties must enter Firebase as drafts.")
    if not isinstance(record.get("monthlyRent"), (int, float)) or record["monthlyRent"] <= 0:
        raise ValueError("Every property requires a positive monthlyRent.")
    if not isinstance(record.get("bedrooms"), int) or not 0 <= record["bedrooms"] <= 20:
        raise ValueError("Every property requires a valid bedrooms count.")
    if not isinstance(record.get("bathrooms"), int) or not 1 <= record["bathrooms"] <= 20:
        raise ValueError("Every property requires a valid bathrooms count.")
    facilities = record.get("facilities")
    image_urls = record.get("imageUrls")
    if not isinstance(facilities, list) or not all(isinstance(value, str) for value in facilities):
        raise ValueError("facilities must be a string array.")
    if image_urls != []:
        raise ValueError("Controlled drafts must start without remote image URLs.")
    if record.get("ratingAverage") != 0 or record.get("ratingCount") != 0:
        raise ValueError("Controlled drafts must start without ratings.")
    return dict(record)


def seed_properties(*, agent_id: str, project_id: str, dataset_path: Path = DATASET_PATH) -> int:
    if not agent_id.strip() or not project_id.strip():
        raise ValueError("agent_id and project_id are required.")
    records = load_dataset(dataset_path)
    initialize(project_id.strip())
    database = firestore.client()
    batch = database.batch()
    for record in records:
        property_id = f"demo-{agent_id.strip()}-{record.pop('demoId')}"
        reference = database.collection("properties").document(property_id)
        batch.set(
            reference,
            {
                **record,
                "agentId": agent_id.strip(),
                "createdAt": firestore.SERVER_TIMESTAMP,
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
        )
    batch.commit()
    return len(records)


def main() -> None:
    args = parse_args()
    count = seed_properties(
        agent_id=args.agent_id,
        project_id=args.project_id,
        dataset_path=args.dataset,
    )
    print(f"Seeded {count} controlled property drafts.")


if __name__ == "__main__":
    main()

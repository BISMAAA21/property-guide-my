import argparse
import re

_MODEL_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Cache the reviewed CLIP processor and weights in a container image."
    )
    parser.add_argument("--model-id", required=True)
    return parser.parse_args()


def cache_model(model_id: str) -> None:
    if not _MODEL_ID.fullmatch(model_id):
        raise ValueError("The model ID must be a simple owner/model Hugging Face identifier.")

    from transformers import AutoProcessor, CLIPModel

    AutoProcessor.from_pretrained(model_id)
    CLIPModel.from_pretrained(model_id)


if __name__ == "__main__":
    cache_model(parse_args().model_id)

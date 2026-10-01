# syntax=docker/dockerfile:1.7

FROM python:3.11-slim-bookworm

ARG CLIP_MODEL_ID=openai/clip-vit-base-patch32

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    HF_HOME=/opt/huggingface \
    HF_HUB_DISABLE_TELEMETRY=1 \
    BAKED_CLIP_MODEL_ID=${CLIP_MODEL_ID} \
    VISION_MODEL_ID=${CLIP_MODEL_ID} \
    DAMAGE_MODEL_ID=${CLIP_MODEL_ID} \
    PRELOAD_VISION_MODELS=true

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        libgomp1 \
        tesseract-ocr \
        tesseract-ocr-eng \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt requirements-ai.txt ./
RUN python -m pip install --no-cache-dir \
        --index-url https://download.pytorch.org/whl/cpu \
        "torch>=2.7,<3" \
    && python -m pip install --no-cache-dir -r requirements-ai.txt

COPY scripts/cache_clip_model.py scripts/cache_clip_model.py
RUN python scripts/cache_clip_model.py --model-id "${CLIP_MODEL_ID}" \
    && rm scripts/cache_clip_model.py

ENV HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1

COPY app app

RUN useradd --create-home --uid 10001 appuser \
    && chown -R appuser:appuser /opt/huggingface /app

USER appuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:' + __import__('os').environ.get('PORT', '8080') + '/health', timeout=4)"

CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080} --workers 1"]

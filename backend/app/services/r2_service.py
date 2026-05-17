"""Cloudflare R2 presigned uploads (S3-compatible API)."""

from __future__ import annotations

import logging
import uuid
from typing import Any

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from app.config import settings

logger = logging.getLogger(__name__)

VOICE_CONTENT_TYPE = "audio/x-m4a"
PRESIGN_EXPIRES_SECONDS = 300


def r2_configured() -> bool:
    return bool(
        settings.r2_account_id
        and settings.r2_access_key_id
        and settings.r2_secret_access_key
        and settings.r2_bucket_name
        and settings.r2_public_base_url
    )


def _s3_client() -> Any:
    endpoint = f"https://{settings.r2_account_id}.r2.cloudflarestorage.com"
    return boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=settings.r2_access_key_id,
        aws_secret_access_key=settings.r2_secret_access_key,
        region_name="auto",
        config=Config(signature_version="s3v4"),
    )


def voice_object_key(*, user_id: int, plan_id: int) -> str:
    return f"voice/{user_id}/{plan_id}/{uuid.uuid4().hex}.m4a"


def public_object_url(object_key: str) -> str:
    base = settings.r2_public_base_url.rstrip("/")
    return f"{base}/{object_key.lstrip('/')}"


def create_voice_presigned_put(*, user_id: int, plan_id: int) -> tuple[str, str, str]:
    """Returns (presigned_put_url, object_key, public_voice_url)."""
    if not r2_configured():
        raise RuntimeError("R2 is not configured")
    object_key = voice_object_key(user_id=user_id, plan_id=plan_id)
    client = _s3_client()
    try:
        upload_url = client.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": settings.r2_bucket_name,
                "Key": object_key,
                "ContentType": VOICE_CONTENT_TYPE,
            },
            ExpiresIn=PRESIGN_EXPIRES_SECONDS,
            HttpMethod="PUT",
        )
    except (BotoCoreError, ClientError) as exc:
        logger.exception("r2: presign failed for plan %s: %s", plan_id, exc)
        raise RuntimeError("Failed to create upload URL") from exc
    return upload_url, object_key, public_object_url(object_key)

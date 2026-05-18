"""Cloudflare R2 presigned uploads (S3-compatible API)."""

from __future__ import annotations

import json
import logging
import time
import uuid
from typing import Any

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from app.config import settings

logger = logging.getLogger(__name__)

VOICE_CONTENT_TYPE = "audio/x-m4a"
PRESIGN_EXPIRES_SECONDS = 300
PRESIGN_GET_EXPIRES_SECONDS = 3600


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


def family_voice_object_key(
    *,
    caregiver_id: int,
    elder_id: int,
    timestamp_ms: int | None = None,
) -> str:
    """voice/{A_id}/{B_id}_{timestamp}_family_voice.m4a — A=caregiver, B=elder."""
    ts = timestamp_ms if timestamp_ms is not None else int(time.time() * 1000)
    return f"voice/{caregiver_id}/{elder_id}_{ts}_family_voice.m4a"


def legacy_family_voice_object_key(*, elder_id: int) -> str:
    """Pre–per-caregiver uploads: voice/{elder_id}/family_voice.m4a."""
    return f"voice/{elder_id}/family_voice.m4a"


def voice_object_key(*, user_id: int, plan_id: int) -> str:
    return f"voice/{user_id}/{plan_id}/{uuid.uuid4().hex}.m4a"


def public_object_url(object_key: str) -> str:
    base = settings.r2_public_base_url.rstrip("/")
    return f"{base}/{object_key.lstrip('/')}"


def weekly_summary_object_key(elder_id: int, year: int, week_num: int) -> str:
    return f"summaries/{elder_id}/{year}_w{week_num}.json"


def upload_weekly_summary_json(
    *,
    elder_id: int,
    year: int,
    week_num: int,
    payload: dict,
) -> str | None:
    """Upload weekly summary JSON snapshot; returns public URL or None if R2 unavailable."""
    if not r2_configured():
        logger.warning("R2 not configured; skip weekly summary snapshot for elder %s", elder_id)
        return None
    object_key = weekly_summary_object_key(elder_id, year, week_num)
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    client = _s3_client()
    try:
        client.put_object(
            Bucket=settings.r2_bucket_name,
            Key=object_key,
            Body=body,
            ContentType="application/json",
        )
        url = public_object_url(object_key)
        logger.info(
            "weekly summary snapshot uploaded: elder=%s key=%s", elder_id, object_key
        )
        return url
    except (BotoCoreError, ClientError) as exc:
        logger.exception(
            "r2: weekly summary upload failed elder=%s key=%s: %s",
            elder_id,
            object_key,
            exc,
        )
        return None


def object_key_from_stored_public_url(stored_url: str) -> str | None:
    """Parse object key from a URL under R2_PUBLIC_BASE_URL."""
    if not settings.r2_public_base_url:
        return None
    base = settings.r2_public_base_url.rstrip("/")
    url = stored_url.strip()
    prefix = f"{base}/"
    if url.startswith(prefix):
        return url[len(prefix) :].lstrip("/")
    return None


def create_presigned_get(*, object_key: str) -> str:
    """Short-lived signed GET for mobile download (no public bucket required)."""
    if not r2_configured():
        raise RuntimeError("R2 is not configured")
    client = _s3_client()
    try:
        return client.generate_presigned_url(
            "get_object",
            Params={
                "Bucket": settings.r2_bucket_name,
                "Key": object_key,
            },
            ExpiresIn=PRESIGN_GET_EXPIRES_SECONDS,
            HttpMethod="GET",
        )
    except (BotoCoreError, ClientError) as exc:
        logger.exception("r2: presign GET failed key=%s: %s", object_key, exc)
        raise RuntimeError("Failed to create download URL") from exc


def resolve_voice_download_url(*, user_id: int, stored_url: str | None) -> str | None:
    """Return a URL the app can GET for playback (presigned when R2 is configured)."""
    if not stored_url or not stored_url.strip():
        return None
    url = stored_url.strip()
    if not r2_configured():
        return url
    object_key = object_key_from_stored_public_url(url)
    if not object_key:
        object_key = legacy_family_voice_object_key(elder_id=user_id)
    try:
        return create_presigned_get(object_key=object_key)
    except RuntimeError as exc:
        logger.warning(
            "r2: presigned GET fallback to stored url user_id=%s: %s", user_id, exc
        )
        return url


def create_family_voice_presigned_put(
    *, caregiver_id: int, elder_id: int
) -> tuple[str, str, str]:
    """Returns (presigned_put_url, object_key, public_voice_url)."""
    if not r2_configured():
        raise RuntimeError("R2 is not configured")
    object_key = family_voice_object_key(
        caregiver_id=caregiver_id, elder_id=elder_id
    )
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
        logger.exception("r2: presign failed for user %s: %s", user_id, exc)
        raise RuntimeError("Failed to create upload URL") from exc
    return upload_url, object_key, public_object_url(object_key)


def create_voice_presigned_put(*, user_id: int, plan_id: int) -> tuple[str, str, str]:
    """Legacy per-plan upload; prefer [create_family_voice_presigned_put]."""
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

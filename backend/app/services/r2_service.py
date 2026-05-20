"""Cloudflare R2 presigned uploads (S3-compatible API)."""

from __future__ import annotations

import json
import logging
import time
import uuid
from threading import Lock
from typing import Any

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from app.config import settings

logger = logging.getLogger(__name__)

VOICE_CONTENT_TYPE = "audio/x-m4a"
PRESIGN_EXPIRES_SECONDS = 300
PRESIGN_GET_EXPIRES_SECONDS = 3600
_s3_client_lock = Lock()
_s3_clients: dict[tuple[str, str, str], Any] = {}


def r2_configured() -> bool:
    return bool(
        settings.r2_account_id
        and settings.r2_access_key_id
        and settings.r2_secret_access_key
        and settings.r2_bucket_name
        and settings.r2_public_base_url
    )


def _s3_client_cache_key() -> tuple[str, str, str]:
    if not (
        settings.r2_account_id
        and settings.r2_access_key_id
        and settings.r2_secret_access_key
    ):
        raise RuntimeError("R2 is not configured")
    endpoint = f"https://{settings.r2_account_id}.r2.cloudflarestorage.com"
    return (
        endpoint,
        settings.r2_access_key_id,
        settings.r2_secret_access_key,
    )


def get_s3_client() -> Any:
    """Return a cached R2 S3 client (reuses botocore's underlying HTTP pool)."""
    key = _s3_client_cache_key()
    with _s3_client_lock:
        cached = _s3_clients.get(key)
        if cached is not None:
            return cached
        client = boto3.client(
            "s3",
            endpoint_url=key[0],
            aws_access_key_id=key[1],
            aws_secret_access_key=key[2],
            region_name="auto",
            config=Config(signature_version="s3v4"),
        )
        _s3_clients[key] = client
        return client


def close_s3_clients() -> None:
    with _s3_client_lock:
        for client in _s3_clients.values():
            try:
                client.close()
            except Exception as exc:
                logger.debug("r2: s3 client close: %s", exc)
        _s3_clients.clear()


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


def list_weekly_summary_object_keys(elder_id: int) -> set[str]:
    """List existing weekly summary snapshot keys for one elder with a single prefix scan."""
    if not r2_configured():
        return set()
    prefix = f"summaries/{elder_id}/"
    client = get_s3_client()
    keys: set[str] = set()
    continuation_token: str | None = None
    try:
        while True:
            kwargs: dict[str, Any] = {
                "Bucket": settings.r2_bucket_name,
                "Prefix": prefix,
            }
            if continuation_token:
                kwargs["ContinuationToken"] = continuation_token
            resp = client.list_objects_v2(**kwargs)
            for obj in resp.get("Contents", []) or []:
                key = obj.get("Key")
                if isinstance(key, str):
                    keys.add(key)
            if not resp.get("IsTruncated"):
                break
            token = resp.get("NextContinuationToken")
            if not isinstance(token, str) or not token:
                break
            continuation_token = token
    except (BotoCoreError, ClientError) as exc:
        logger.warning("r2: list weekly summary objects failed elder=%s: %s", elder_id, exc)
        return set()
    return keys


def weekly_summary_object_exists(object_key: str) -> bool:
    """HEAD object in R2; False if missing or R2 not configured."""
    if not r2_configured():
        return False
    client = get_s3_client()
    try:
        client.head_object(Bucket=settings.r2_bucket_name, Key=object_key)
        return True
    except ClientError as exc:
        code = (exc.response.get("Error") or {}).get("Code", "")
        if code in ("404", "NoSuchKey", "NotFound"):
            return False
        logger.warning("r2: head_object failed key=%s code=%s", object_key, code)
        return False
    except (BotoCoreError, Exception) as exc:
        logger.warning("r2: head_object failed key=%s: %s", object_key, exc)
        return False


def fetch_weekly_summary_json_from_r2(object_key: str) -> dict | None:
    """Read a frozen weekly summary JSON object from R2 (server-side credentials)."""
    if not r2_configured():
        return None
    client = get_s3_client()
    try:
        resp = client.get_object(Bucket=settings.r2_bucket_name, Key=object_key)
        raw = resp["Body"].read().decode("utf-8")
        data = json.loads(raw)
        if isinstance(data, dict):
            return data
        logger.warning("r2: weekly summary JSON is not an object key=%s", object_key)
        return None
    except ClientError as exc:
        code = (exc.response.get("Error") or {}).get("Code", "")
        if code in ("404", "NoSuchKey", "NotFound"):
            return None
        logger.warning("r2: get_object failed key=%s code=%s", object_key, code)
        return None
    except (BotoCoreError, json.JSONDecodeError, Exception) as exc:
        logger.warning("r2: get_object failed key=%s: %s", object_key, exc)
        return None


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
    client = get_s3_client()
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


def delete_object_by_key(object_key: str) -> None:
    """Best-effort delete of one R2 object; ignores missing keys."""
    if not r2_configured() or not object_key.strip():
        return
    client = _s3_client()
    try:
        client.delete_object(Bucket=settings.r2_bucket_name, Key=object_key.lstrip("/"))
    except ClientError as exc:
        code = (exc.response.get("Error") or {}).get("Code", "")
        if code in ("404", "NoSuchKey", "NotFound"):
            return
        logger.warning("r2: delete_object failed key=%s code=%s", object_key, code)
    except (BotoCoreError, Exception) as exc:
        logger.warning("r2: delete_object failed key=%s: %s", object_key, exc)


def delete_stored_voice_url(stored_url: str) -> None:
    """Delete R2 object referenced by a stored public voice URL."""
    key = object_key_from_stored_public_url(stored_url)
    if key:
        delete_object_by_key(key)


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
    client = get_s3_client()
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
    client = get_s3_client()
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
    client = get_s3_client()
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

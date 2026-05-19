"""
PRO elder health snapshot in Redis Hash.

Key: ``elder:snapshot:{elder_id}`` (Hash, no TTL — write-driven updates only).

Fields:
  - ``vitals``: JSON — latest BP/BS readings and measured_at timestamps.
  - ``medications``: JSON — today's medication progress summary + slot items.
  - ``updated_at``: ISO 8601 UTC timestamp of the last snapshot write.
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Any

from sqlalchemy.orm import Session

from app.database import SessionLocal
from app.redis_client import get_async_redis
from app.schemas.medication import TodayMedicationItem
from app.schemas.snapshot import ClinicalSnapshotRead
from app.schemas.vital import BloodPressureRead, BloodSugarRead
from app.services.clinical_snapshot_service import (
    build_clinical_snapshot,
    build_medications_snapshot_payload,
    build_vitals_snapshot_payload,
)

logger = logging.getLogger(__name__)

SNAPSHOT_KEY_PREFIX = "elder:snapshot"


def snapshot_key(elder_id: int) -> str:
    return f"{SNAPSHOT_KEY_PREFIX}:{elder_id}"


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def schedule_snapshot_coro(coro) -> None:
    """Fire-and-forget async Redis work (safe from sync routes / BackgroundTasks)."""

    async def _run() -> None:
        try:
            await coro
        except Exception as exc:
            logger.warning("elder snapshot: background sync failed: %s", exc)

    try:
        loop = asyncio.get_running_loop()
        loop.create_task(_run())
    except RuntimeError:
        asyncio.run(_run())


async def _hset_snapshot(elder_id: int, mapping: dict[str, str]) -> None:
    try:
        redis = get_async_redis()
        await redis.hset(snapshot_key(elder_id), mapping=mapping)
    except Exception as exc:
        logger.warning(
            "elder snapshot: hset failed elder=%s: %s", elder_id, exc,
        )


async def sync_vitals_snapshot(
    elder_id: int,
    *,
    blood_pressure: BloodPressureRead | None = None,
    blood_sugar: BloodSugarRead | None = None,
) -> None:
    """Merge latest vitals into the hash after a BP/BS write."""
    if blood_pressure is None and blood_sugar is None:
        return
    try:
        redis = get_async_redis()
        key = snapshot_key(elder_id)
        vitals: dict[str, Any] = {
            "latest_blood_pressure": None,
            "latest_blood_sugar": None,
        }
        try:
            raw = await redis.hget(key, "vitals")
            if raw:
                parsed = json.loads(raw)
                if isinstance(parsed, dict):
                    vitals = parsed
        except Exception as exc:
            logger.debug("elder snapshot: read existing vitals failed: %s", exc)

        if blood_pressure is not None:
            vitals["latest_blood_pressure"] = blood_pressure.model_dump(mode="json")
        if blood_sugar is not None:
            vitals["latest_blood_sugar"] = blood_sugar.model_dump(mode="json")

        await _hset_snapshot(
            elder_id,
            {
                "vitals": json.dumps(vitals, default=str),
                "updated_at": _utc_now_iso(),
            },
        )
    except Exception as exc:
        logger.warning(
            "elder snapshot: vitals sync failed elder=%s: %s", elder_id, exc,
        )


async def sync_medications_snapshot_from_db(elder_id: int) -> None:
    """Rebuild medications field from Neon after a check-in change."""
    try:
        db = SessionLocal()
        try:
            payload = build_medications_snapshot_payload(db, elder_id)
        finally:
            db.close()
        await _hset_snapshot(
            elder_id,
            {
                "medications": json.dumps(payload, default=str),
                "updated_at": _utc_now_iso(),
            },
        )
    except Exception as exc:
        logger.warning(
            "elder snapshot: medications sync failed elder=%s: %s", elder_id, exc,
        )


async def write_full_snapshot_from_db(elder_id: int) -> None:
    """Populate vitals + medications + updated_at (cache warm / repair)."""
    try:
        db = SessionLocal()
        try:
            vitals = build_vitals_snapshot_payload(db, elder_id)
            medications = build_medications_snapshot_payload(db, elder_id)
        finally:
            db.close()
        await _hset_snapshot(
            elder_id,
            {
                "vitals": json.dumps(vitals, default=str),
                "medications": json.dumps(medications, default=str),
                "updated_at": _utc_now_iso(),
            },
        )
    except Exception as exc:
        logger.warning(
            "elder snapshot: full warm failed elder=%s: %s", elder_id, exc,
        )


def _parse_vitals_field(raw: str | None) -> tuple[BloodPressureRead | None, BloodSugarRead | None]:
    if not raw:
        return None, None
    data = json.loads(raw)
    if not isinstance(data, dict):
        return None, None
    bp_raw = data.get("latest_blood_pressure")
    bs_raw = data.get("latest_blood_sugar")
    bp = BloodPressureRead.model_validate(bp_raw) if bp_raw else None
    bs = BloodSugarRead.model_validate(bs_raw) if bs_raw else None
    return bp, bs


def _parse_medications_field(raw: str | None) -> list[TodayMedicationItem]:
    if not raw:
        return []
    data = json.loads(raw)
    if not isinstance(data, dict):
        return []
    items_raw = data.get("items") or []
    return [TodayMedicationItem.model_validate(item) for item in items_raw]


def _parse_updated_at(raw: str | None) -> datetime:
    if raw:
        try:
            return datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except ValueError:
            pass
    return datetime.now(timezone.utc)


async def read_clinical_snapshot_from_redis(elder_id: int) -> ClinicalSnapshotRead | None:
    """
  Return a clinical snapshot assembled from Redis, or None on cache miss.

  Miss: key absent or hash empty. Partial fields deserialize with safe defaults.
    """
    redis = get_async_redis()
    key = snapshot_key(elder_id)
    try:
        data = await redis.hgetall(key)
    except Exception as exc:
        logger.warning("elder snapshot: hgetall failed elder=%s: %s", elder_id, exc)
        raise

    if not data:
        return None

    vitals_raw = data.get("vitals")
    meds_raw = data.get("medications")
    # Partial hash (e.g. only vitals after BP) → treat as miss; reader will warm full snapshot.
    if not vitals_raw or not meds_raw:
        return None

    bp, bs = _parse_vitals_field(vitals_raw)
    med_items = _parse_medications_field(meds_raw)
    generated_at = _parse_updated_at(data.get("updated_at"))

    return ClinicalSnapshotRead(
        user_id=elder_id,
        latest_blood_pressure=bp,
        latest_blood_sugar=bs,
        medications_today=med_items,
        generated_at=generated_at,
    )


async def load_clinical_snapshot(
    db: Session,
    elder_id: int,
    *,
    warm_on_miss: bool = True,
) -> ClinicalSnapshotRead:
    """Redis-first read with Neon fallback and optional background warm."""
    try:
        cached = await read_clinical_snapshot_from_redis(elder_id)
        if cached is not None:
            return cached
    except Exception:
        logger.warning(
            "elder snapshot: redis read failed, degrading to DB elder=%s",
            elder_id,
            exc_info=True,
        )

    snapshot = build_clinical_snapshot(db, elder_id)
    if warm_on_miss:
        schedule_snapshot_coro(write_full_snapshot_from_db(elder_id))
    return snapshot


def schedule_vitals_sync_after_bp(row) -> None:
    try:
        bp = BloodPressureRead.model_validate(row)
        schedule_snapshot_coro(
            sync_vitals_snapshot(bp.user_id, blood_pressure=bp),
        )
    except Exception as exc:
        logger.warning("elder snapshot: schedule bp sync failed: %s", exc)


def schedule_vitals_sync_after_bs(row) -> None:
    try:
        bs = BloodSugarRead.model_validate(row)
        schedule_snapshot_coro(
            sync_vitals_snapshot(bs.user_id, blood_sugar=bs),
        )
    except Exception as exc:
        logger.warning("elder snapshot: schedule bs sync failed: %s", exc)


def schedule_vitals_rebuild_from_db(elder_id: int) -> None:
    async def _job() -> None:
        db = SessionLocal()
        try:
            vitals = build_vitals_snapshot_payload(db, elder_id)
        finally:
            db.close()
        await _hset_snapshot(
            elder_id,
            {
                "vitals": json.dumps(vitals, default=str),
                "updated_at": _utc_now_iso(),
            },
        )

    try:
        schedule_snapshot_coro(_job())
    except Exception as exc:
        logger.warning("elder snapshot: schedule vitals rebuild failed: %s", exc)


def schedule_medications_sync(elder_id: int) -> None:
    try:
        schedule_snapshot_coro(sync_medications_snapshot_from_db(elder_id))
    except Exception as exc:
        logger.warning("elder snapshot: schedule medications sync failed: %s", exc)

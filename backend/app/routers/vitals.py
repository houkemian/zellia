import logging
from typing import Annotated
from datetime import datetime, timezone

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, Response
from sqlalchemy import func, select
from sqlalchemy.orm import Session, noload

from app.database import SessionLocal, get_db
from app.dependencies import get_current_user
from app.models import BloodPressureRecord, BloodSugarRecord, FamilyLink, User
from app.services.elder_snapshot_service import (
    schedule_vitals_rebuild_from_db,
    schedule_vitals_sync_after_bp,
    schedule_vitals_sync_after_bs,
)
from app.services.notification_service import notify_caregivers_for_abnormal_vitals
from app.schemas.vital import (
    BloodPressureCreate,
    BloodPressureListResponse,
    BloodPressureRead,
    BloodSugarCreate,
    BloodSugarListResponse,
    BloodSugarRead,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/vitals", tags=["vitals"])

# Performance notes (vitals_bp avalanche fixes):
# - GET /vitals/bp: noload(record.user); composite index (user_id, measured_at) via Alembic migration.
# - POST /vitals/bp: FCM alert runs in BackgroundTasks (was blocking request + thread pool).


def _resolve_target_user_id(db: Session, current_user: User, target_user_id: int | None) -> int:
    if target_user_id is None or target_user_id == current_user.id:
        return current_user.id
    try:
        approved = db.execute(
            select(FamilyLink.id).where(
                FamilyLink.caregiver_id == current_user.id,
                FamilyLink.elder_id == target_user_id,
                FamilyLink.status == "APPROVED",
            )
        ).first()
    except Exception as exc:
        logger.exception("vitals: family permission check failed: %s", exc)
        raise HTTPException(status_code=500, detail="Permission check failed") from exc
    if approved is None:
        raise HTTPException(status_code=403, detail="No permission to view target user")
    return target_user_id


def _elder_display_name(user: User) -> str:
    nickname = (user.nickname or "").strip()
    return nickname or user.username


def _resolve_created_at_local(
    payload_created_at_local: datetime | None,
    payload_measured_at: datetime | None,
) -> datetime | None:
    if payload_created_at_local is not None:
        return payload_created_at_local.astimezone(timezone.utc)
    if payload_measured_at is not None:
        return payload_measured_at.astimezone(timezone.utc)
    return None


def _server_now() -> datetime:
    return datetime.now(timezone.utc)


def _notify_abnormal_vitals_background(
    *,
    elder_id: int,
    elder_name: str,
    alert_text: str,
    payload: dict[str, str],
) -> None:
    db = SessionLocal()
    try:
        notify_caregivers_for_abnormal_vitals(
            db=db,
            elder_id=elder_id,
            elder_name=elder_name,
            alert_text=alert_text,
            payload=payload,
        )
    except Exception as exc:
        logger.warning("vitals: background abnormal-vitals notify failed: %s", exc)
    finally:
        db.close()


@router.post("/bp", response_model=BloodPressureRead)
def create_bp(
    payload: BloodPressureCreate,
    background_tasks: BackgroundTasks,
    response: Response,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    if payload.idempotency_key:
        existing = db.execute(
            select(BloodPressureRecord).where(
                BloodPressureRecord.idempotency_key == payload.idempotency_key,
            )
        ).scalar_one_or_none()
        if existing is not None:
            response.status_code = 200
            return BloodPressureRead.model_validate(existing)

    server_measured_at = _server_now()
    created_at_local = _resolve_created_at_local(
        payload.created_at_local,
        payload.measured_at,
    )
    row = BloodPressureRecord(
        user_id=current_user.id,
        systolic=payload.systolic,
        diastolic=payload.diastolic,
        heart_rate=payload.heart_rate,
        measured_at=server_measured_at,
        idempotency_key=payload.idempotency_key,
        created_at_local=created_at_local,
    )
    try:
        db.add(row)
        db.commit()
        db.refresh(row)
    except Exception as exc:
        db.rollback()
        if payload.idempotency_key:
            existing = db.execute(
                select(BloodPressureRecord).where(
                    BloodPressureRecord.idempotency_key == payload.idempotency_key,
                )
            ).scalar_one_or_none()
            if existing is not None:
                response.status_code = 200
                return BloodPressureRead.model_validate(existing)
        logger.exception("vitals: create_bp failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to save blood pressure") from exc

    response.status_code = 201
    if row.systolic > 140 or row.systolic < 90 or row.diastolic > 90 or row.diastolic < 60:
        background_tasks.add_task(
            _notify_abnormal_vitals_background,
            elder_id=current_user.id,
            elder_name=_elder_display_name(current_user),
            alert_text=f"血压数值异常 ({row.systolic}/{row.diastolic})",
            payload={
                "type": "vital_bp_abnormal",
                "elder_id": str(current_user.id),
                "systolic": str(row.systolic),
                "diastolic": str(row.diastolic),
            },
        )

    schedule_vitals_sync_after_bp(row)
    return BloodPressureRead.model_validate(row)


@router.get("/bp", response_model=BloodPressureListResponse)
def list_bp(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
    target_user_id: int | None = None,
):
    user_id = _resolve_target_user_id(db, current_user, target_user_id)
    offset = (page - 1) * page_size
    try:
        total = db.scalar(
            select(func.count())
            .select_from(BloodPressureRecord)
            .where(
                BloodPressureRecord.user_id == user_id,
                BloodPressureRecord.is_deleted.is_(False),
            )
        )
        rows = db.execute(
            select(BloodPressureRecord)
            .where(
                BloodPressureRecord.user_id == user_id,
                BloodPressureRecord.is_deleted.is_(False),
            )
            .options(noload(BloodPressureRecord.user))
            .order_by(BloodPressureRecord.measured_at.desc())
            .offset(offset)
            .limit(page_size)
        ).scalars().all()
    except Exception as exc:
        logger.exception("vitals: list_bp failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to load blood pressure records") from exc
    return BloodPressureListResponse(
        items=[BloodPressureRead.model_validate(row) for row in rows],
        total=int(total or 0),
        page=page,
        page_size=page_size,
    )


@router.post("/bs", response_model=BloodSugarRead)
def create_bs(
    payload: BloodSugarCreate,
    background_tasks: BackgroundTasks,
    response: Response,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    if payload.idempotency_key:
        existing = db.execute(
            select(BloodSugarRecord).where(
                BloodSugarRecord.idempotency_key == payload.idempotency_key,
            )
        ).scalar_one_or_none()
        if existing is not None:
            response.status_code = 200
            return BloodSugarRead.model_validate(existing)

    server_measured_at = _server_now()
    created_at_local = _resolve_created_at_local(
        payload.created_at_local,
        payload.measured_at,
    )
    row = BloodSugarRecord(
        user_id=current_user.id,
        level=payload.level,
        condition=payload.condition,
        measured_at=server_measured_at,
        idempotency_key=payload.idempotency_key,
        created_at_local=created_at_local,
    )
    try:
        db.add(row)
        db.commit()
        db.refresh(row)
    except Exception as exc:
        db.rollback()
        if payload.idempotency_key:
            existing = db.execute(
                select(BloodSugarRecord).where(
                    BloodSugarRecord.idempotency_key == payload.idempotency_key,
                )
            ).scalar_one_or_none()
            if existing is not None:
                response.status_code = 200
                return BloodSugarRead.model_validate(existing)
        logger.exception("vitals: create_bs failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to save blood sugar") from exc

    response.status_code = 201
    high_threshold = 6.1 if row.condition in ("fasting", "空腹", "Fasting") else 7.8
    if row.level < 3.9 or row.level > high_threshold:
        background_tasks.add_task(
            _notify_abnormal_vitals_background,
            elder_id=current_user.id,
            elder_name=_elder_display_name(current_user),
            alert_text=f"血糖数值异常 ({row.level:.1f} mmol/L)",
            payload={
                "type": "vital_bs_abnormal",
                "elder_id": str(current_user.id),
                "level": f"{row.level:.1f}",
            },
        )

    schedule_vitals_sync_after_bs(row)
    return BloodSugarRead.model_validate(row)


@router.get("/bs", response_model=BloodSugarListResponse)
def list_bs(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    page: Annotated[int, Query(ge=1)] = 1,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
    target_user_id: int | None = None,
):
    user_id = _resolve_target_user_id(db, current_user, target_user_id)
    offset = (page - 1) * page_size
    try:
        total = db.scalar(
            select(func.count())
            .select_from(BloodSugarRecord)
            .where(
                BloodSugarRecord.user_id == user_id,
                BloodSugarRecord.is_deleted.is_(False),
            )
        )
        rows = db.execute(
            select(BloodSugarRecord)
            .where(
                BloodSugarRecord.user_id == user_id,
                BloodSugarRecord.is_deleted.is_(False),
            )
            .options(noload(BloodSugarRecord.user))
            .order_by(BloodSugarRecord.measured_at.desc())
            .offset(offset)
            .limit(page_size)
        ).scalars().all()
    except Exception as exc:
        logger.exception("vitals: list_bs failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to load blood sugar records") from exc
    return BloodSugarListResponse(
        items=[BloodSugarRead.model_validate(row) for row in rows],
        total=int(total or 0),
        page=page,
        page_size=page_size,
    )


@router.delete("/bp/{record_id}", status_code=204)
def delete_bp(
    record_id: int,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    try:
        row = db.get(BloodPressureRecord, record_id)
        if row is None or row.user_id != current_user.id or row.is_deleted:
            raise HTTPException(status_code=404, detail="Blood pressure record not found")
        elder_id = row.user_id
        row.is_deleted = True
        row.deleted_at = datetime.now(timezone.utc)
        row.deleted_by_user_id = current_user.id
        db.commit()
        schedule_vitals_rebuild_from_db(elder_id)
    except HTTPException:
        raise
    except Exception as exc:
        db.rollback()
        logger.exception("vitals: delete_bp failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to delete blood pressure record") from exc


@router.delete("/bs/{record_id}", status_code=204)
def delete_bs(
    record_id: int,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    try:
        row = db.get(BloodSugarRecord, record_id)
        if row is None or row.user_id != current_user.id or row.is_deleted:
            raise HTTPException(status_code=404, detail="Blood sugar record not found")
        elder_id = row.user_id
        row.is_deleted = True
        row.deleted_at = datetime.now(timezone.utc)
        row.deleted_by_user_id = current_user.id
        db.commit()
        schedule_vitals_rebuild_from_db(elder_id)
    except HTTPException:
        raise
    except Exception as exc:
        db.rollback()
        logger.exception("vitals: delete_bs failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to delete blood sugar record") from exc

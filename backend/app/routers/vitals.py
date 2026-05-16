import logging
from typing import Annotated
from datetime import timezone

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session, noload

from app.database import SessionLocal, get_db
from app.dependencies import get_current_user
from app.models import BloodPressureRecord, BloodSugarRecord, FamilyLink, User
from app.services.notification_service import notify_caregivers_for_abnormal_vitals
from app.schemas.vital import BloodPressureCreate, BloodPressureRead, BloodSugarCreate, BloodSugarRead

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/vitals", tags=["vitals"])

# Performance notes (vitals_bp avalanche fixes):
# - GET /vitals/bp: noload(record.user); composite index (user_id, measured_at) via schema_bootstrap.
# - POST /vitals/bp: FCM alert runs in BackgroundTasks (was blocking request + thread pool).
# - Root cause elsewhere: get_current_user no longer runs DDL every request (schema_bootstrap cache).


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


@router.post("/bp", response_model=BloodPressureRead, status_code=201)
def create_bp(
    payload: BloodPressureCreate,
    background_tasks: BackgroundTasks,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    row = BloodPressureRecord(
        user_id=current_user.id,
        systolic=payload.systolic,
        diastolic=payload.diastolic,
        heart_rate=payload.heart_rate,
        measured_at=payload.measured_at.astimezone(timezone.utc),
    )
    try:
        db.add(row)
        db.commit()
        db.refresh(row)
    except Exception as exc:
        db.rollback()
        logger.exception("vitals: create_bp failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to save blood pressure") from exc

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

    return BloodPressureRead.model_validate(row)


@router.get("/bp", response_model=list[BloodPressureRead])
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
        rows = db.execute(
            select(BloodPressureRecord)
            .where(BloodPressureRecord.user_id == user_id)
            .options(noload(BloodPressureRecord.user))
            .order_by(BloodPressureRecord.measured_at.desc())
            .offset(offset)
            .limit(page_size)
        ).scalars().all()
    except Exception as exc:
        logger.exception("vitals: list_bp failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to load blood pressure records") from exc
    return [BloodPressureRead.model_validate(row) for row in rows]


@router.post("/bs", response_model=BloodSugarRead, status_code=201)
def create_bs(
    payload: BloodSugarCreate,
    background_tasks: BackgroundTasks,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    row = BloodSugarRecord(
        user_id=current_user.id,
        level=payload.level,
        condition=payload.condition,
        measured_at=payload.measured_at.astimezone(timezone.utc),
    )
    try:
        db.add(row)
        db.commit()
        db.refresh(row)
    except Exception as exc:
        db.rollback()
        logger.exception("vitals: create_bs failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to save blood sugar") from exc

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

    return BloodSugarRead.model_validate(row)


@router.get("/bs", response_model=list[BloodSugarRead])
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
        rows = db.execute(
            select(BloodSugarRecord)
            .where(BloodSugarRecord.user_id == user_id)
            .options(noload(BloodSugarRecord.user))
            .order_by(BloodSugarRecord.measured_at.desc())
            .offset(offset)
            .limit(page_size)
        ).scalars().all()
    except Exception as exc:
        logger.exception("vitals: list_bs failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to load blood sugar records") from exc
    return [BloodSugarRead.model_validate(row) for row in rows]


@router.delete("/bp/{record_id}", status_code=204)
def delete_bp(
    record_id: int,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    try:
        row = db.get(BloodPressureRecord, record_id)
        if row is None or row.user_id != current_user.id:
            raise HTTPException(status_code=404, detail="Blood pressure record not found")
        db.delete(row)
        db.commit()
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
        if row is None or row.user_id != current_user.id:
            raise HTTPException(status_code=404, detail="Blood sugar record not found")
        db.delete(row)
        db.commit()
    except HTTPException:
        raise
    except Exception as exc:
        db.rollback()
        logger.exception("vitals: delete_bs failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to delete blood sugar record") from exc

import logging
from datetime import date, datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session, noload

from app.database import get_db
from app.dependencies import get_current_user, require_pro_user
from app.models import BloodPressureRecord, BloodSugarRecord, FamilyLink, MedicationLog, MedicationPlan, User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/reports", tags=["reports"])

# N+1 mitigations in this module:
# - build_clinical_summary / GET /reports/clinical-summary:
#   * patient row via select(User.id, username, nickname) — no full User ORM graph.
#   * MedicationPlan query: noload(user|logs).
#   * BloodPressureRecord / BloodSugarRecord lists: noload(user) — dict response only.


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
        logger.exception("reports: family permission check failed: %s", exc)
        raise HTTPException(status_code=500, detail="Permission check failed") from exc
    if approved is None:
        raise HTTPException(status_code=403, detail="No permission to view target user")
    return target_user_id


def _times_per_day(times_a_day: str) -> int:
    return len([part for part in (raw.strip() for raw in times_a_day.split(",")) if part])


def build_clinical_summary(db: Session, user_id: int, days: int = 30) -> dict:
    end_date = datetime.now(timezone.utc).date()
    start_date = end_date - timedelta(days=days - 1)
    start_dt = datetime.combine(start_date, datetime.min.time(), tzinfo=timezone.utc)

    try:
        patient_row = db.execute(
            select(User.id, User.username, User.nickname).where(User.id == user_id)
        ).one_or_none()
    except Exception as exc:
        logger.exception("clinical-summary: load patient failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to load patient profile") from exc

    if patient_row is None:
        raise HTTPException(status_code=404, detail="Target user not found")

    patient_id, patient_username, patient_nickname = patient_row
    display_name = (patient_nickname or "").strip() or patient_username

    try:
        plans = db.execute(
            select(MedicationPlan)
            .where(
                MedicationPlan.user_id == user_id,
                MedicationPlan.start_date <= end_date,
                MedicationPlan.end_date >= start_date,
            )
            .options(
                noload(MedicationPlan.user),
                noload(MedicationPlan.logs),
            )
        ).scalars().all()

        total_tasks = 0
        for plan in plans:
            overlap_start = max(plan.start_date, start_date)
            overlap_end = min(plan.end_date, end_date)
            if overlap_start > overlap_end:
                continue
            span_days = (overlap_end - overlap_start).days + 1
            total_tasks += span_days * _times_per_day(plan.times_a_day)

        taken_count = db.execute(
            select(func.count(MedicationLog.id)).where(
                MedicationLog.user_id == user_id,
                MedicationLog.is_taken.is_(True),
                MedicationLog.taken_date >= start_date,
                MedicationLog.taken_date <= end_date,
            )
        ).scalar_one()

        bp_rows = db.execute(
            select(BloodPressureRecord)
            .where(
                BloodPressureRecord.user_id == user_id,
                BloodPressureRecord.measured_at >= start_dt,
            )
            .options(noload(BloodPressureRecord.user))
            .order_by(BloodPressureRecord.measured_at.desc())
        ).scalars().all()

        bs_rows = db.execute(
            select(BloodSugarRecord)
            .where(
                BloodSugarRecord.user_id == user_id,
                BloodSugarRecord.measured_at >= start_dt,
            )
            .options(noload(BloodSugarRecord.user))
            .order_by(BloodSugarRecord.measured_at.desc())
        ).scalars().all()
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("clinical-summary: aggregate queries failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to build clinical summary") from exc

    adherence_percent = round((taken_count / total_tasks) * 100, 1) if total_tasks > 0 else 0.0

    avg_systolic = round(sum(row.systolic for row in bp_rows) / len(bp_rows), 1) if bp_rows else None
    avg_diastolic = round(sum(row.diastolic for row in bp_rows) / len(bp_rows), 1) if bp_rows else None
    hr_values = [row.heart_rate for row in bp_rows if row.heart_rate is not None]
    avg_heart_rate = round(sum(hr_values) / len(hr_values), 1) if hr_values else None
    bp_abnormal_count = sum(
        1
        for row in bp_rows
        if row.systolic > 140 or row.systolic < 90 or row.diastolic > 90 or row.diastolic < 60
    )

    return {
        "days": days,
        "patient": {
            "user_id": patient_id,
            "username": patient_username,
            "nickname": (patient_nickname or "").strip() or None,
            "display_name": display_name,
        },
        "period": {
            "start_date": start_date.isoformat(),
            "end_date": end_date.isoformat(),
        },
        "medication_adherence": {
            "taken_count": taken_count,
            "total_tasks": total_tasks,
            "percent": adherence_percent,
        },
        "blood_pressure_summary": {
            "average_systolic": avg_systolic,
            "average_diastolic": avg_diastolic,
            "average_heart_rate": avg_heart_rate,
            "abnormal_count": bp_abnormal_count,
        },
        "blood_pressure_records": [
            {
                "id": row.id,
                "systolic": row.systolic,
                "diastolic": row.diastolic,
                "heart_rate": row.heart_rate,
                "measured_at": row.measured_at.isoformat(),
            }
            for row in bp_rows
        ],
        "blood_sugar_records": [
            {
                "id": row.id,
                "level": row.level,
                "condition": row.condition,
                "measured_at": row.measured_at.isoformat(),
            }
            for row in bs_rows
        ],
    }


@router.get("/clinical-summary")
def clinical_summary(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(require_pro_user)],
    days: Annotated[int, Query(ge=1, le=365)] = 30,
    target_user_id: Annotated[int | None, Query()] = None,
):
    user_id = _resolve_target_user_id(db, current_user, target_user_id)
    try:
        return build_clinical_summary(db, user_id, days)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("clinical_summary endpoint failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to load clinical summary") from exc

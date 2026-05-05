from datetime import date, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, require_pro_user
from app.models import BloodPressureRecord, BloodSugarRecord, FamilyLink, MedicationLog, MedicationPlan, User

router = APIRouter(prefix="/reports", tags=["reports"])


def _resolve_target_user_id(db: Session, current_user: User, target_user_id: int | None) -> int:
    if target_user_id is None or target_user_id == current_user.id:
        return current_user.id
    approved = db.execute(
        select(FamilyLink.id).where(
            FamilyLink.caregiver_id == current_user.id,
            FamilyLink.elder_id == target_user_id,
            FamilyLink.status == "APPROVED",
        )
    ).first()
    if approved is None:
        raise HTTPException(status_code=403, detail="No permission to view target user")
    return target_user_id


def _times_per_day(times_a_day: str) -> int:
    return len([part for part in (raw.strip() for raw in times_a_day.split(",")) if part])


def build_clinical_summary(db: Session, user_id: int, days: int = 30) -> dict:
    end_date = date.today()
    start_date = end_date - timedelta(days=days - 1)
    start_dt = datetime.combine(start_date, datetime.min.time())

    report_user = db.get(User, user_id)
    if report_user is None:
        raise HTTPException(status_code=404, detail="Target user not found")

    plans = db.execute(
        select(MedicationPlan).where(
            MedicationPlan.user_id == user_id,
            MedicationPlan.start_date <= end_date,
            MedicationPlan.end_date >= start_date,
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

    adherence_percent = round((taken_count / total_tasks) * 100, 1) if total_tasks > 0 else 0.0

    bp_rows = db.execute(
        select(BloodPressureRecord)
        .where(
            BloodPressureRecord.user_id == user_id,
            BloodPressureRecord.measured_at >= start_dt,
        )
        .order_by(BloodPressureRecord.measured_at.desc())
    ).scalars().all()

    bs_rows = db.execute(
        select(BloodSugarRecord)
        .where(
            BloodSugarRecord.user_id == user_id,
            BloodSugarRecord.measured_at >= start_dt,
        )
        .order_by(BloodSugarRecord.measured_at.desc())
    ).scalars().all()

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
            "user_id": user_id,
            "username": report_user.username,
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
    return build_clinical_summary(db, user_id, days)

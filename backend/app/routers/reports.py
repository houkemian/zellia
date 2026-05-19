import logging
from datetime import date, datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.orm import Session, noload

from app.database import get_db
from app.dependencies import get_current_user, require_pro_user
from app.models import BloodPressureRecord, BloodSugarRecord, FamilyLink, MedicationLog, MedicationPlan, User
from app.schemas.reports import WeeklySummaryListItem, WeeklySummaryResponse
from app.services.weekly_summary_service import build_weekly_summary, build_weekly_summary_list

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/reports", tags=["reports"])

# N+1 mitigations in this module:
# - build_clinical_summary / GET /reports/clinical-summary:
#   * patient row via select(User.id, username, nickname) — no full User ORM graph.
#   * MedicationPlan query: noload(user|logs).
#   * BloodPressureRecord / BloodSugarRecord lists: noload(user) — dict response only.
#   * Aggregate stats (avg, count, abnormal) computed at DB level; record lists paginated.


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


def build_clinical_summary(
    db: Session,
    user_id: int,
    days: int = 30,
    record_page: int = 1,
    record_page_size: int = 50,
) -> dict:
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

        # ── DB-level aggregates (no per-row loading for summary stats) ──
        bp_agg = db.execute(
            select(
                func.count(BloodPressureRecord.id),
                func.avg(BloodPressureRecord.systolic),
                func.avg(BloodPressureRecord.diastolic),
                func.avg(
                    case(
                        (BloodPressureRecord.heart_rate.is_not(None), BloodPressureRecord.heart_rate),
                        else_=None,
                    )
                ),
                func.sum(
                    case(
                        (or_(
                            BloodPressureRecord.systolic > 140,
                            BloodPressureRecord.systolic < 90,
                            BloodPressureRecord.diastolic > 90,
                            BloodPressureRecord.diastolic < 60,
                        ), 1),
                        else_=0,
                    )
                ),
            )
            .where(
                BloodPressureRecord.user_id == user_id,
                BloodPressureRecord.measured_at >= start_dt,
            )
        ).one()

        bs_agg = db.execute(
            select(
                func.count(BloodSugarRecord.id),
                func.avg(BloodSugarRecord.level),
                func.sum(
                    case(
                        (BloodSugarRecord.level < 3.9, 1),
                        (and_(
                            BloodSugarRecord.condition.in_(["fasting", "空腹", "Fasting"]),
                            BloodSugarRecord.level > 6.1,
                        ), 1),
                        (and_(
                            ~BloodSugarRecord.condition.in_(["fasting", "空腹", "Fasting"]),
                            BloodSugarRecord.level > 7.8,
                        ), 1),
                        else_=0,
                    )
                ),
            )
            .where(
                BloodSugarRecord.user_id == user_id,
                BloodSugarRecord.measured_at >= start_dt,
            )
        ).one()

        # ── Paginated record lists ──
        bp_offset = (record_page - 1) * record_page_size
        bp_rows = db.execute(
            select(BloodPressureRecord)
            .where(
                BloodPressureRecord.user_id == user_id,
                BloodPressureRecord.measured_at >= start_dt,
            )
            .options(noload(BloodPressureRecord.user))
            .order_by(BloodPressureRecord.measured_at.desc())
            .offset(bp_offset)
            .limit(record_page_size)
        ).scalars().all()

        bs_rows = db.execute(
            select(BloodSugarRecord)
            .where(
                BloodSugarRecord.user_id == user_id,
                BloodSugarRecord.measured_at >= start_dt,
            )
            .options(noload(BloodSugarRecord.user))
            .order_by(BloodSugarRecord.measured_at.desc())
            .offset(bp_offset)
            .limit(record_page_size)
        ).scalars().all()

    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("clinical-summary: aggregate queries failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to build clinical summary") from exc

    def _round_optional(value) -> float | None:
        if value is None:
            return None
        return round(float(value), 1)

    bp_count = int(bp_agg[0] or 0)
    bs_count = int(bs_agg[0] or 0)
    adherence_percent = round((taken_count / total_tasks) * 100, 1) if total_tasks > 0 else 0.0

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
            "total_count": bp_count,
            "average_systolic": _round_optional(bp_agg[1]),
            "average_diastolic": _round_optional(bp_agg[2]),
            "average_heart_rate": _round_optional(bp_agg[3]),
            "abnormal_count": int(bp_agg[4] or 0),
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
        "blood_sugar_summary": {
            "total_count": bs_count,
            "average_level": _round_optional(bs_agg[1]),
            "abnormal_count": int(bs_agg[2] or 0),
        },
        "blood_sugar_records": [
            {
                "id": row.id,
                "level": row.level,
                "condition": row.condition,
                "measured_at": row.measured_at.isoformat(),
            }
            for row in bs_rows
        ],
        "record_pagination": {
            "page": record_page,
            "page_size": record_page_size,
        },
    }


@router.get("/weekly-summary", response_model=WeeklySummaryResponse)
def weekly_summary(
    response: Response,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    days: Annotated[int, Query(ge=1, le=30)] = 7,
    target_user_id: Annotated[int | None, Query()] = None,
    iso_year: Annotated[int | None, Query(ge=2000, le=2100)] = None,
    iso_week: Annotated[int | None, Query(ge=1, le=53)] = None,
):
    response.headers["Cache-Control"] = "public, max-age=60"
    user_id = _resolve_target_user_id(db, current_user, target_user_id)
    if (iso_year is None) ^ (iso_week is None):
        raise HTTPException(
            status_code=400,
            detail="iso_year and iso_week must be provided together",
        )
    try:
        return build_weekly_summary(
            db,
            user_id,
            days=days,
            iso_year=iso_year,
            iso_week=iso_week,
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("weekly_summary endpoint failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to load weekly summary") from exc


@router.get("/weekly-summary/list", response_model=list[WeeklySummaryListItem])
def weekly_summary_list(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    target_user_id: Annotated[int, Query()],
):
    user_id = _resolve_target_user_id(db, current_user, target_user_id)
    live_path = f"/reports/weekly-summary?target_user_id={user_id}"
    return build_weekly_summary_list(user_id, live_api_path=live_path)


@router.get("/clinical-summary")
def clinical_summary(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(require_pro_user)],
    days: Annotated[int, Query(ge=1, le=365)] = 30,
    target_user_id: Annotated[int | None, Query()] = None,
    record_page: Annotated[int, Query(ge=1)] = 1,
    record_page_size: Annotated[int, Query(ge=1, le=100)] = 50,
):
    user_id = _resolve_target_user_id(db, current_user, target_user_id)
    try:
        return build_clinical_summary(
            db, user_id, days=days,
            record_page=record_page, record_page_size=record_page_size,
        )
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("clinical_summary endpoint failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to load clinical summary") from exc

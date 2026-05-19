"""Weekly health summary: DB-level aggregates + FCM push + R2 snapshots."""

import logging
from datetime import date, datetime, timedelta, timezone

from sqlalchemy import and_, case, func, or_, select
from sqlalchemy.orm import Session

from app.schemas.reports import WeeklySummaryResponse
from app.services.r2_service import (
    public_object_url,
    r2_configured,
    upload_weekly_summary_json,
    weekly_summary_object_exists,
    weekly_summary_object_key,
)
from app.models import (
    BloodPressureRecord,
    BloodSugarRecord,
    FamilyLink,
    MedicationLog,
    MedicationPlan,
    User,
)
from app.services.notification_service import notify_caregivers_weekly_summary

logger = logging.getLogger(__name__)

_DAYS_DEFAULT = 7
_LIST_WEEKS = 4
_FASTING_CONDITIONS = ("fasting", "空腹", "Fasting")


def _times_per_day(times_a_day: str) -> int:
    return len([part for part in (raw.strip() for raw in times_a_day.split(",")) if part])


def week_period(days: int = _DAYS_DEFAULT) -> tuple[date, date]:
    end_date = datetime.now(timezone.utc).date()
    start_date = end_date - timedelta(days=days - 1)
    return start_date, end_date


def iso_week_period(iso_year: int, iso_week: int) -> tuple[date, date]:
    start_date = date.fromisocalendar(iso_year, iso_week, 1)
    end_date = date.fromisocalendar(iso_year, iso_week, 7)
    return start_date, end_date


def _medication_total_tasks(
    db: Session,
    user_id: int,
    start_date: date,
    end_date: date,
) -> int:
    rows = db.execute(
        select(
            MedicationPlan.start_date,
            MedicationPlan.end_date,
            MedicationPlan.times_a_day,
        ).where(
            MedicationPlan.user_id == user_id,
            MedicationPlan.start_date <= end_date,
            MedicationPlan.end_date >= start_date,
        )
    ).all()
    total = 0
    for plan_start, plan_end, times_a_day in rows:
        overlap_start = max(plan_start, start_date)
        overlap_end = min(plan_end, end_date)
        if overlap_start > overlap_end:
            continue
        span_days = (overlap_end - overlap_start).days + 1
        total += span_days * _times_per_day(times_a_day or "")
    return total


def _bs_abnormal_expr():
    fasting = BloodSugarRecord.condition.in_(_FASTING_CONDITIONS)
    return case(
        (BloodSugarRecord.level < 3.9, 1),
        (and_(fasting, BloodSugarRecord.level > 6.1), 1),
        (and_(~fasting, BloodSugarRecord.level > 7.8), 1),
        else_=0,
    )


def _bp_abnormal_expr():
    return case(
        (
            or_(
                BloodPressureRecord.systolic > 140,
                BloodPressureRecord.systolic < 90,
                BloodPressureRecord.diastolic > 90,
                BloodPressureRecord.diastolic < 60,
            ),
            1,
        ),
        else_=0,
    )


def build_weekly_summary(
    db: Session,
    user_id: int,
    days: int = _DAYS_DEFAULT,
    *,
    iso_year: int | None = None,
    iso_week: int | None = None,
) -> dict:
    if (iso_year is None) ^ (iso_week is None):
        raise ValueError("iso_year and iso_week must be provided together")

    if iso_year is not None and iso_week is not None:
        start_date, end_date = iso_week_period(iso_year, iso_week)
        days = (end_date - start_date).days + 1
    else:
        start_date, end_date = week_period(days)

    start_dt = datetime.combine(start_date, datetime.min.time(), tzinfo=timezone.utc)
    end_dt = datetime.combine(end_date, datetime.max.time(), tzinfo=timezone.utc)

    patient_row = db.execute(
        select(User.id, User.username, User.nickname).where(User.id == user_id)
    ).one_or_none()
    if patient_row is None:
        raise ValueError(f"user {user_id} not found")
    patient_id, patient_username, patient_nickname = patient_row
    display_name = (patient_nickname or "").strip() or patient_username

    taken_count = db.execute(
        select(func.count(MedicationLog.id)).where(
            MedicationLog.user_id == user_id,
            MedicationLog.is_taken.is_(True),
            MedicationLog.taken_date >= start_date,
            MedicationLog.taken_date <= end_date,
        )
    ).scalar_one()

    total_tasks = _medication_total_tasks(db, user_id, start_date, end_date)
    missed_count = max(0, int(total_tasks) - int(taken_count)) if total_tasks > 0 else 0
    adherence_percent = (
        round((taken_count / total_tasks) * 100, 1) if total_tasks > 0 else 0.0
    )

    bp_row = db.execute(
        select(
            func.avg(BloodPressureRecord.systolic),
            func.avg(BloodPressureRecord.diastolic),
            func.avg(
                case(
                    (BloodPressureRecord.heart_rate.is_not(None), BloodPressureRecord.heart_rate),
                    else_=None,
                )
            ),
            func.count(BloodPressureRecord.id),
            func.sum(_bp_abnormal_expr()),
        ).where(
            BloodPressureRecord.user_id == user_id,
            BloodPressureRecord.measured_at >= start_dt,
            BloodPressureRecord.measured_at <= end_dt,
        )
    ).one()

    bs_row = db.execute(
        select(
            func.avg(BloodSugarRecord.level),
            func.count(BloodSugarRecord.id),
            func.sum(_bs_abnormal_expr()),
        ).where(
            BloodSugarRecord.user_id == user_id,
            BloodSugarRecord.measured_at >= start_dt,
            BloodSugarRecord.measured_at <= end_dt,
        )
    ).one()

    def _round_optional(value) -> float | None:
        if value is None:
            return None
        return round(float(value), 1)

    bp_abnormal = int(bp_row[4] or 0)
    bs_abnormal = int(bs_row[2] or 0)

    iso_year, iso_week, _ = end_date.isocalendar()
    payload = {
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
        "medication": {
            "taken_count": int(taken_count),
            "total_tasks": int(total_tasks),
            "missed_count": missed_count,
            "adherence_percent": adherence_percent,
        },
        "blood_pressure": {
            "average_systolic": _round_optional(bp_row[0]),
            "average_diastolic": _round_optional(bp_row[1]),
            "average_heart_rate": _round_optional(bp_row[2]),
            "record_count": int(bp_row[3] or 0),
            "abnormal_count": bp_abnormal,
        },
        "blood_sugar": {
            "average_level": _round_optional(bs_row[0]),
            "record_count": int(bs_row[1] or 0),
            "abnormal_count": bs_abnormal,
        },
        "iso_year": iso_year,
        "iso_week": iso_week,
    }
    return WeeklySummaryResponse.model_validate(payload).model_dump()


def freeze_weekly_summary_to_r2(elder_id: int, summary: dict) -> str | None:
    """Persist summary JSON to R2 using ISO week of period end_date."""
    period = summary.get("period") or {}
    end_raw = period.get("end_date")
    if not end_raw:
        logger.warning("freeze_weekly_summary: missing end_date for elder %s", elder_id)
        return None
    end_date = date.fromisoformat(str(end_raw))
    iso_year, iso_week, _ = end_date.isocalendar()
    return upload_weekly_summary_json(
        elder_id=elder_id,
        year=iso_year,
        week_num=iso_week,
        payload=summary,
    )


def build_weekly_summary_list(elder_id: int, *, live_api_path: str) -> list[dict]:
    """In-memory week list (no vitals/medication table scans)."""
    today = datetime.now(timezone.utc).date()
    current_year, current_week, _ = today.isocalendar()

    items: list[dict] = [
        {
            "week_label": "本周动态 (进行中)",
            "url": live_api_path,
            "is_frozen": False,
            "snapshot_exists": False,
            "iso_year": current_year,
            "iso_week": current_week,
        }
    ]

    seen: set[tuple[int, int]] = set()
    cursor = today
    while len(seen) < _LIST_WEEKS:
        cursor = cursor - timedelta(days=7)
        year, week, _ = cursor.isocalendar()
        if (year, week) == (current_year, current_week):
            continue
        if (year, week) in seen:
            continue
        seen.add((year, week))
        week_start = date.fromisocalendar(year, week, 1)
        week_end = date.fromisocalendar(year, week, 7)
        label = (
            f"{year}年第{week}周 "
            f"({week_start.strftime('%m/%d')} - {week_end.strftime('%m/%d')})"
        )
        object_key = weekly_summary_object_key(elder_id, year, week)
        if r2_configured():
            frozen_url = public_object_url(object_key)
            snapshot_exists = weekly_summary_object_exists(object_key)
        else:
            frozen_url = ""
            snapshot_exists = False
        items.append(
            {
                "week_label": label,
                "url": frozen_url,
                "is_frozen": True,
                "snapshot_exists": snapshot_exists,
                "iso_year": year,
                "iso_week": week,
            }
        )
    return items


def weekly_summary_push_body(elder_display_name: str, summary: dict) -> str:
    med = summary["medication"]
    missed = med["missed_count"]
    pct = med["adherence_percent"]
    bp_abn = summary["blood_pressure"]["abnormal_count"]
    bs_abn = summary["blood_sugar"]["abnormal_count"]
    name = elder_display_name.strip() or "Ta"

    if missed > 0:
        return (
            f"⚠️ {name} 这周漏服了 {missed} 次药，"
            f"花 1 分钟看看本周总结，给 Ta 送去一句叮嘱吧。"
        )
    if pct >= 100 and bp_abn == 0 and bs_abn == 0:
        return (
            f"✅ {name} 这周 100% 按时服药啦！血压也很平稳，"
            f"花 1 分钟看看本周的健康小结吧。"
        )
    if pct >= 95 and bp_abn == 0 and bs_abn == 0:
        return (
            f"✅ {name} 这周 {pct:.0f}% 按时服药，体征平稳，"
            f"花 1 分钟看看本周的健康小结吧。"
        )
    if bp_abn > 0 or bs_abn > 0:
        return (
            f"💙 {name} 本周有 {bp_abn + bs_abn} 次体征波动值得关注，"
            f"花 1 分钟看看本周健康小结吧。"
        )
    return f"💙 {name} 的本周健康小结已准备好，花 1 分钟看看吧。"


def send_weekly_summary_pushes(db: Session, days: int = _DAYS_DEFAULT) -> None:
    links = db.execute(
        select(FamilyLink.elder_id, FamilyLink.caregiver_id, FamilyLink.elder_alias).where(
            FamilyLink.status == "APPROVED",
        )
    ).all()
    if not links:
        return

    elder_ids = {row.elder_id for row in links}
    summaries: dict[int, dict] = {}
    for elder_id in elder_ids:
        try:
            summary = build_weekly_summary(db, elder_id, days=days)
            summaries[elder_id] = summary
            freeze_weekly_summary_to_r2(elder_id, summary)
        except Exception as exc:
            logger.exception("weekly summary build failed for elder %s: %s", elder_id, exc)

    for elder_id, caregiver_id, elder_alias in links:
        summary = summaries.get(elder_id)
        if summary is None:
            continue
        display = (elder_alias or "").strip() or summary["patient"]["display_name"]
        body = weekly_summary_push_body(display, summary)
        period = summary["period"]
        notify_caregivers_weekly_summary(
            db=db,
            elder_id=elder_id,
            caregiver_id=caregiver_id,
            body=body,
            week_start=period["start_date"],
        )

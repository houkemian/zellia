import logging
from datetime import date, datetime, time, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session, noload

from app.models import BloodPressureRecord, BloodSugarRecord, MedicationLog, MedicationPlan
from app.schemas.medication import TodayMedicationItem
from app.schemas.snapshot import ClinicalSnapshotRead
from app.schemas.vital import BloodPressureRead, BloodSugarRead

logger = logging.getLogger(__name__)


def _parse_time_slot(raw: str) -> time:
    parts = raw.strip().split(":")
    h = int(parts[0])
    m = int(parts[1]) if len(parts) > 1 else 0
    return time(h, m)


def _format_time(t: time) -> str:
    return f"{t.hour:02d}:{t.minute:02d}"


def _batch_logs_for_today(
    db: Session,
    *,
    user_id: int,
    today: date,
    plan_ids: list[int],
) -> dict[tuple[int, time], MedicationLog]:
    if not plan_ids:
        return {}
    logs = db.execute(
        select(MedicationLog)
        .where(
            MedicationLog.user_id == user_id,
            MedicationLog.taken_date == today,
            MedicationLog.plan_id.in_(plan_ids),
        )
        .options(
            noload(MedicationLog.plan),
            noload(MedicationLog.user),
        )
        .order_by(
            MedicationLog.plan_id,
            MedicationLog.taken_time,
            MedicationLog.id.desc(),
        )
    ).scalars().all()
    log_map: dict[tuple[int, time], MedicationLog] = {}
    for log in logs:
        key = (log.plan_id, log.taken_time)
        if key not in log_map:
            log_map[key] = log
    return log_map


def _load_medications_today(db: Session, user_id: int) -> list[TodayMedicationItem]:
    today = datetime.now(timezone.utc).date()
    plans = db.execute(
        select(MedicationPlan)
        .where(
            MedicationPlan.user_id == user_id,
            MedicationPlan.is_active.is_(True),
            MedicationPlan.start_date <= today,
            MedicationPlan.end_date >= today,
        )
        .options(
            noload(MedicationPlan.user),
            noload(MedicationPlan.logs),
        )
    ).scalars().all()
    log_map = _batch_logs_for_today(
        db,
        user_id=user_id,
        today=today,
        plan_ids=[plan.id for plan in plans],
    )
    items: list[TodayMedicationItem] = []
    for plan in plans:
        slots = [s for s in (x.strip() for x in plan.times_a_day.split(",")) if s]
        for slot in slots:
            try:
                tt = _parse_time_slot(slot)
            except (ValueError, IndexError):
                continue
            log = log_map.get((plan.id, tt))
            items.append(
                TodayMedicationItem(
                    plan_id=plan.id,
                    name=plan.name,
                    dosage=plan.dosage,
                    scheduled_time=_format_time(tt),
                    taken_date=today,
                    log_id=log.id if log else None,
                    is_taken=log.is_taken if log else None,
                    checked_at=log.checked_at if log else None,
                    notify_missed=bool(plan.notify_missed),
                    notify_delay_minutes=int(plan.notify_delay_minutes or 60),
                )
            )
    items.sort(key=lambda x: x.scheduled_time)
    return items


def build_vitals_snapshot_payload(db: Session, user_id: int) -> dict:
    """Minimal vitals dict for Redis ``vitals`` hash field."""
    bp_row = db.execute(
        select(BloodPressureRecord)
        .where(
            BloodPressureRecord.user_id == user_id,
            BloodPressureRecord.is_deleted.is_(False),
        )
        .options(noload(BloodPressureRecord.user))
        .order_by(BloodPressureRecord.measured_at.desc())
        .limit(1)
    ).scalars().first()

    bs_row = db.execute(
        select(BloodSugarRecord)
        .where(
            BloodSugarRecord.user_id == user_id,
            BloodSugarRecord.is_deleted.is_(False),
        )
        .options(noload(BloodSugarRecord.user))
        .order_by(BloodSugarRecord.measured_at.desc())
        .limit(1)
    ).scalars().first()

    return {
        "latest_blood_pressure": (
            BloodPressureRead.model_validate(bp_row).model_dump(mode="json")
            if bp_row is not None
            else None
        ),
        "latest_blood_sugar": (
            BloodSugarRead.model_validate(bs_row).model_dump(mode="json")
            if bs_row is not None
            else None
        ),
    }


def build_medications_snapshot_payload(db: Session, user_id: int) -> dict:
    """Today's medication progress summary + slot items for Redis ``medications`` field."""
    items = _load_medications_today(db, user_id)
    total = len(items)
    taken = sum(1 for item in items if item.is_taken)
    latest_checked_at: datetime | None = None
    for item in items:
        if item.checked_at is None:
            continue
        if latest_checked_at is None or item.checked_at > latest_checked_at:
            latest_checked_at = item.checked_at
    return {
        "taken_count": taken,
        "total_count": total,
        "latest_checked_at": (
            latest_checked_at.isoformat() if latest_checked_at is not None else None
        ),
        "items": [item.model_dump(mode="json") for item in items],
    }


def build_clinical_snapshot(db: Session, user_id: int) -> ClinicalSnapshotRead:
    vitals = build_vitals_snapshot_payload(db, user_id)
    try:
        med_payload = build_medications_snapshot_payload(db, user_id)
        med_items = [
            TodayMedicationItem.model_validate(item)
            for item in med_payload.get("items") or []
        ]
    except Exception as exc:
        logger.exception("clinical snapshot: medications_today failed: %s", exc)
        raise

    bp_raw = vitals.get("latest_blood_pressure")
    bs_raw = vitals.get("latest_blood_sugar")

    return ClinicalSnapshotRead(
        user_id=user_id,
        latest_blood_pressure=(
            BloodPressureRead.model_validate(bp_raw) if bp_raw else None
        ),
        latest_blood_sugar=(
            BloodSugarRead.model_validate(bs_raw) if bs_raw else None
        ),
        medications_today=med_items,
        generated_at=datetime.now(timezone.utc),
    )

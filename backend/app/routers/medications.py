from datetime import date, datetime, time, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import delete, inspect, select, text
from sqlalchemy.orm import Session
from redis import Redis

from app.config import settings
from app.dependencies import get_current_user
from app.models import DeviceToken, FamilyLink, MedicationLog, MedicationPlan, MedicationPokeEvent, User
from app.schemas.medication import (
    MedicationLogCreate,
    MedicationPlanCreate,
    MedicationPlanRead,
    MedicationPlanUpdate,
    TodayMedicationItem,
)
from app.database import get_db
from app.services.notification_service import send_poke_to_elder

router = APIRouter(prefix="/medications", tags=["medications"])


def _ensure_checked_at_column(db: Session) -> None:
    columns = {col["name"] for col in inspect(db.bind).get_columns("medication_logs")}
    if "checked_at" in columns:
        return
    db.execute(text("ALTER TABLE medication_logs ADD COLUMN checked_at TIMESTAMP WITH TIME ZONE"))
    db.commit()


def _ensure_medication_notify_columns(db: Session) -> None:
    columns = {col["name"] for col in inspect(db.bind).get_columns("medication_plans")}
    if "notify_missed" not in columns:
        db.execute(text("ALTER TABLE medication_plans ADD COLUMN notify_missed BOOLEAN DEFAULT TRUE"))
        db.commit()
        db.execute(text("UPDATE medication_plans SET notify_missed = TRUE WHERE notify_missed IS NULL"))
        db.commit()
    if "notify_delay_minutes" not in columns:
        db.execute(text("ALTER TABLE medication_plans ADD COLUMN notify_delay_minutes INTEGER DEFAULT 60"))
        db.commit()
        db.execute(text("UPDATE medication_plans SET notify_delay_minutes = 60 WHERE notify_delay_minutes IS NULL"))
        db.commit()


def _parse_time_slot(s: str) -> time:
    raw = s.strip()
    if not raw:
        raise ValueError("empty time")
    parts = raw.split(":")
    h = int(parts[0])
    m = int(parts[1]) if len(parts) > 1 else 0
    return time(h, m)


def _format_time(t: time) -> str:
    return f"{t.hour:02d}:{t.minute:02d}"


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


def _resolve_manage_target_user_id(db: Session, current_user: User, target_user_id: int | None) -> int:
    if target_user_id is None or target_user_id == current_user.id:
        return current_user.id
    approved = db.execute(
        select(FamilyLink.id).where(
            FamilyLink.caregiver_id == current_user.id,
            FamilyLink.elder_id == target_user_id,
            FamilyLink.status == "APPROVED",
            FamilyLink.permissions.in_(("MANAGE", "APPROVED")),
        )
    ).first()
    if approved is None:
        raise HTTPException(status_code=403, detail="您没有权限为该用户管理计划")
    return target_user_id


@router.post("/plan", response_model=MedicationPlanRead, status_code=status.HTTP_201_CREATED)
def create_plan(
    payload: MedicationPlanCreate,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_medication_notify_columns(db)
    target_user_id = _resolve_manage_target_user_id(db, current_user, payload.target_user_id)
    plan = MedicationPlan(
        user_id=target_user_id,
        name=payload.name,
        dosage=payload.dosage,
        start_date=payload.start_date,
        end_date=payload.end_date,
        times_a_day=payload.times_a_day,
        notify_missed=payload.notify_missed,
        notify_delay_minutes=payload.notify_delay_minutes,
        is_active=True,
    )
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return plan


@router.get("/plan", response_model=list[MedicationPlanRead])
def list_plans(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_medication_notify_columns(db)
    rows = db.execute(
        select(MedicationPlan).where(MedicationPlan.user_id == current_user.id).order_by(MedicationPlan.id)
    ).scalars().all()
    return list(rows)


@router.delete("/plan/{plan_id}", status_code=status.HTTP_204_NO_CONTENT)
def soft_delete_plan(
    plan_id: int,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    target_user_id: Annotated[int | None, Query()] = None,
):
    _ensure_medication_notify_columns(db)
    managed_user_id = _resolve_manage_target_user_id(db, current_user, target_user_id)
    plan = db.get(MedicationPlan, plan_id)
    if plan is None or plan.user_id != managed_user_id:
        raise HTTPException(status_code=404, detail="Plan not found")
    plan.is_active = False
    db.commit()
    return None


@router.put("/plan/{plan_id}", response_model=MedicationPlanRead)
def update_plan(
    plan_id: int,
    payload: MedicationPlanUpdate,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_medication_notify_columns(db)
    managed_user_id = _resolve_manage_target_user_id(db, current_user, payload.target_user_id)
    plan = db.get(MedicationPlan, plan_id)
    if plan is None or plan.user_id != managed_user_id:
        raise HTTPException(status_code=404, detail="Plan not found")
    plan.name = payload.name
    plan.dosage = payload.dosage
    plan.start_date = payload.start_date
    plan.end_date = payload.end_date
    plan.times_a_day = payload.times_a_day
    plan.notify_missed = payload.notify_missed
    plan.notify_delay_minutes = payload.notify_delay_minutes
    db.commit()
    db.refresh(plan)
    return plan


@router.get("/today", response_model=list[TodayMedicationItem])
def medications_today(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    target_user_id: Annotated[int | None, Query()] = None,
):
    _ensure_checked_at_column(db)
    _ensure_medication_notify_columns(db)
    user_id = _resolve_target_user_id(db, current_user, target_user_id)
    today = date.today()
    plans = db.execute(
        select(MedicationPlan).where(
            MedicationPlan.user_id == user_id,
            MedicationPlan.is_active.is_(True),
            MedicationPlan.start_date <= today,
            MedicationPlan.end_date >= today,
        )
    ).scalars().all()

    items: list[TodayMedicationItem] = []
    for plan in plans:
        slots = [s for s in (x.strip() for x in plan.times_a_day.split(",")) if s]
        for slot in slots:
            try:
                tt = _parse_time_slot(slot)
            except (ValueError, IndexError):
                continue
            log = db.execute(
                select(MedicationLog)
                .where(
                    MedicationLog.plan_id == plan.id,
                    MedicationLog.user_id == user_id,
                    MedicationLog.taken_date == today,
                    MedicationLog.taken_time == tt,
                )
                .order_by(MedicationLog.id.desc())
                .limit(1)
            ).scalars().first()
            items.append(
                TodayMedicationItem(
                    plan_id=plan.id,
                    name=plan.name,
                    dosage=plan.dosage,
                    scheduled_time=_format_time(tt),
                    taken_date=today,
                    log_id=log.id if log else None,
                    is_taken=log.is_taken if log else None,
                    checked_at=(
                        log.checked_at.strftime("%H:%M")
                        if log and log.checked_at is not None
                        else None
                    ),
                    notify_missed=bool(plan.notify_missed),
                    notify_delay_minutes=int(plan.notify_delay_minutes or 60),
                )
            )
    items.sort(key=lambda x: x.scheduled_time)
    return items


@router.post("/{plan_id}/log", response_model=dict)
def submit_log(
    plan_id: int,
    payload: MedicationLogCreate,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_checked_at_column(db)
    plan = db.get(MedicationPlan, plan_id)
    if plan is None or plan.user_id != current_user.id or not plan.is_active:
        raise HTTPException(status_code=404, detail="Plan not found")

    if payload.is_taken:
        log = db.execute(
            select(MedicationLog)
            .where(
                MedicationLog.plan_id == plan_id,
                MedicationLog.user_id == current_user.id,
                MedicationLog.taken_date == payload.taken_date,
                MedicationLog.taken_time == payload.taken_time,
            )
            .order_by(MedicationLog.id.desc())
            .limit(1)
        ).scalars().first()

        if log:
            log.is_taken = True
            log.checked_at = datetime.now(timezone.utc)
            db.commit()
            db.refresh(log)
            return {"id": log.id, "is_taken": True}
        log = MedicationLog(
            plan_id=plan_id,
            user_id=current_user.id,
            taken_date=payload.taken_date,
            taken_time=payload.taken_time,
            is_taken=True,
            checked_at=datetime.now(timezone.utc),
        )
        db.add(log)
        db.commit()
        db.refresh(log)
        return {"id": log.id, "is_taken": True}

    # Explicit cancel check-in: remove all logs at this timeslot (handles DB duplicates).
    db.execute(
        delete(MedicationLog).where(
            MedicationLog.plan_id == plan_id,
            MedicationLog.user_id == current_user.id,
            MedicationLog.taken_date == payload.taken_date,
            MedicationLog.taken_time == payload.taken_time,
        )
    )
    db.commit()
    return {"id": None, "is_taken": False}


@router.post("/{plan_id}/poke", response_model=dict)
def poke_elder_for_medication(
    plan_id: int,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_medication_notify_columns(db)
    plan = db.get(MedicationPlan, plan_id)
    if plan is None or not plan.is_active:
        raise HTTPException(status_code=404, detail="Plan not found")

    link = db.execute(
        select(FamilyLink).where(
            FamilyLink.caregiver_id == current_user.id,
            FamilyLink.elder_id == plan.user_id,
            FamilyLink.status == "APPROVED",
        )
    ).scalar_one_or_none()
    if link is None:
        raise HTTPException(status_code=403, detail="Only approved caregiver can send reminder")

    cooldown_key = f"medication_poke:{plan_id}"
    try:
        redis_client = Redis.from_url(settings.redis_url, socket_connect_timeout=2, socket_timeout=2)
        lock_ok = bool(redis_client.set(cooldown_key, str(current_user.id), nx=True, ex=600))
        if not lock_ok:
            ttl = redis_client.ttl(cooldown_key)
            remaining = int(ttl) if ttl and ttl > 0 else 600
            return {"ok": False, "cooldown_seconds": remaining, "detail": "Cooldown active"}
    except Exception:
        cutoff = datetime.now(timezone.utc) - timedelta(minutes=10)
        recent = db.execute(
            select(MedicationPokeEvent.id).where(
                MedicationPokeEvent.plan_id == plan_id,
                MedicationPokeEvent.created_at >= cutoff,
            )
        ).first()
        if recent is not None:
            raise HTTPException(status_code=429, detail="Please wait before sending another reminder")

    elder = db.get(User, plan.user_id)
    if elder is None:
        raise HTTPException(status_code=404, detail="Elder not found")

    caregiver_name = (link.caregiver_alias or "").strip() or current_user.username
    title = "服药提醒"
    body = f"您的子女 {caregiver_name} 提醒您服用 {plan.name}"
    tokens = db.execute(
        select(DeviceToken.fcm_token).where(
            DeviceToken.user_id == elder.id,
            DeviceToken.fcm_token.is_not(None),
        )
    ).scalars().all()
    clean_tokens = [token for token in tokens if token and token.strip()]
    send_poke_to_elder(
        clean_tokens,
        title=title,
        body=body,
        data={
            "type": "caregiver_poke",
            "plan_id": str(plan.id),
            "elder_id": str(elder.id),
            "caregiver_id": str(current_user.id),
        },
    )

    db.add(MedicationPokeEvent(plan_id=plan.id, caregiver_id=current_user.id))
    db.commit()
    return {"ok": True, "cooldown_seconds": 600}

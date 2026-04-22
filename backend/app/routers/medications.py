from datetime import date, datetime, time
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import inspect, select, text
from sqlalchemy.orm import Session

from app.dependencies import get_current_user
from app.models import FamilyLink, MedicationLog, MedicationPlan, User
from app.schemas.medication import (
    MedicationLogCreate,
    MedicationPlanCreate,
    MedicationPlanRead,
    TodayMedicationItem,
)
from app.database import get_db

router = APIRouter(prefix="/medications", tags=["medications"])


def _ensure_checked_at_column(db: Session) -> None:
    columns = {col["name"] for col in inspect(db.bind).get_columns("medication_logs")}
    if "checked_at" in columns:
        return
    db.execute(text("ALTER TABLE medication_logs ADD COLUMN checked_at DATETIME"))
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


@router.post("/plan", response_model=MedicationPlanRead, status_code=status.HTTP_201_CREATED)
def create_plan(
    payload: MedicationPlanCreate,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    plan = MedicationPlan(
        user_id=current_user.id,
        name=payload.name,
        dosage=payload.dosage,
        start_date=payload.start_date,
        end_date=payload.end_date,
        times_a_day=payload.times_a_day,
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
    rows = db.execute(
        select(MedicationPlan).where(MedicationPlan.user_id == current_user.id).order_by(MedicationPlan.id)
    ).scalars().all()
    return list(rows)


@router.delete("/plan/{plan_id}", status_code=status.HTTP_204_NO_CONTENT)
def soft_delete_plan(
    plan_id: int,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    plan = db.get(MedicationPlan, plan_id)
    if plan is None or plan.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Plan not found")
    plan.is_active = False
    db.commit()
    return None


@router.get("/today", response_model=list[TodayMedicationItem])
def medications_today(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    target_user_id: Annotated[int | None, Query()] = None,
):
    _ensure_checked_at_column(db)
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
                select(MedicationLog).where(
                    MedicationLog.plan_id == plan.id,
                    MedicationLog.user_id == user_id,
                    MedicationLog.taken_date == today,
                    MedicationLog.taken_time == tt,
                )
            ).scalar_one_or_none()
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

    log = db.execute(
        select(MedicationLog).where(
            MedicationLog.plan_id == plan_id,
            MedicationLog.user_id == current_user.id,
            MedicationLog.taken_date == payload.taken_date,
            MedicationLog.taken_time == payload.taken_time,
        )
    ).scalar_one_or_none()

    if payload.is_taken:
        if log:
            log.is_taken = True
            log.checked_at = datetime.now()
            db.commit()
            db.refresh(log)
            return {"id": log.id, "is_taken": True}
        log = MedicationLog(
            plan_id=plan_id,
            user_id=current_user.id,
            taken_date=payload.taken_date,
            taken_time=payload.taken_time,
            is_taken=True,
            checked_at=datetime.now(),
        )
        db.add(log)
        db.commit()
        db.refresh(log)
        return {"id": log.id, "is_taken": True}

    # Explicit cancel check-in: remove today's log at this timeslot.
    if log:
        db.delete(log)
        db.commit()
    return {"id": None, "is_taken": False}

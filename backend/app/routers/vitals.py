from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models import BloodPressureRecord, BloodSugarRecord, FamilyLink, User
from app.schemas.vital import BloodPressureCreate, BloodPressureRead, BloodSugarCreate, BloodSugarRead

router = APIRouter(prefix="/vitals", tags=["vitals"])


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


@router.post("/bp", response_model=BloodPressureRead, status_code=201)
def create_bp(
    payload: BloodPressureCreate,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    row = BloodPressureRecord(
        user_id=current_user.id,
        systolic=payload.systolic,
        diastolic=payload.diastolic,
        heart_rate=payload.heart_rate,
        measured_at=payload.measured_at,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


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
    rows = db.execute(
        select(BloodPressureRecord)
        .where(BloodPressureRecord.user_id == user_id)
        .order_by(BloodPressureRecord.measured_at.desc())
        .offset(offset)
        .limit(page_size)
    ).scalars().all()
    return list(rows)


@router.post("/bs", response_model=BloodSugarRead, status_code=201)
def create_bs(
    payload: BloodSugarCreate,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    row = BloodSugarRecord(
        user_id=current_user.id,
        level=payload.level,
        condition=payload.condition,
        measured_at=payload.measured_at,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


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
    rows = db.execute(
        select(BloodSugarRecord)
        .where(BloodSugarRecord.user_id == user_id)
        .order_by(BloodSugarRecord.measured_at.desc())
        .offset(offset)
        .limit(page_size)
    ).scalars().all()
    return list(rows)


@router.delete("/bp/{record_id}", status_code=204)
def delete_bp(
    record_id: int,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    row = db.get(BloodPressureRecord, record_id)
    if row is None or row.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Blood pressure record not found")
    db.delete(row)
    db.commit()


@router.delete("/bs/{record_id}", status_code=204)
def delete_bs(
    record_id: int,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    row = db.get(BloodSugarRecord, record_id)
    if row is None or row.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="Blood sugar record not found")
    db.delete(row)
    db.commit()

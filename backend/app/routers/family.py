import secrets
import string
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import inspect, select, text
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models import FamilyLink, User

router = APIRouter(prefix="/family", tags=["family"])


def _ensure_family_schema(db: Session) -> None:
    user_columns = {col["name"] for col in inspect(db.bind).get_columns("users")}
    if "invite_code" not in user_columns:
        db.execute(text("ALTER TABLE users ADD COLUMN invite_code VARCHAR(32)"))
        db.commit()
        db.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_invite_code ON users (invite_code)"))
        db.commit()


def _generate_invite_code(length: int = 8) -> str:
    alphabet = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def _get_or_create_invite_code(db: Session, user: User) -> str:
    _ensure_family_schema(db)
    if user.invite_code:
        return user.invite_code

    for _ in range(20):
        code = _generate_invite_code()
        exists = db.execute(select(User.id).where(User.invite_code == code)).first()
        if exists is None:
            user.invite_code = code
            db.commit()
            db.refresh(user)
            return code
    raise HTTPException(status_code=500, detail="Failed to generate invite code")


class InviteCodeRead(BaseModel):
    invite_code: str


class LinkApplyPayload(BaseModel):
    invite_code: str


class FamilyLinkRead(BaseModel):
    id: int
    elder_id: int
    caregiver_id: int
    status: str
    permissions: str
    elder_username: str
    caregiver_username: str


class LinkDecisionPayload(BaseModel):
    approved: bool


def _to_link_read(link: FamilyLink) -> FamilyLinkRead:
    return FamilyLinkRead(
        id=link.id,
        elder_id=link.elder_id,
        caregiver_id=link.caregiver_id,
        status=link.status,
        permissions=link.permissions,
        elder_username=link.elder.username,
        caregiver_username=link.caregiver.username,
    )


@router.get("/invite-code", response_model=InviteCodeRead)
def get_invite_code(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    code = _get_or_create_invite_code(db, current_user)
    return InviteCodeRead(invite_code=code)


@router.post("/apply", response_model=FamilyLinkRead, status_code=status.HTTP_201_CREATED)
def apply_by_invite_code(
    payload: LinkApplyPayload,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_family_schema(db)
    invite_code = payload.invite_code.strip().upper()
    if not invite_code:
        raise HTTPException(status_code=400, detail="Invite code is required")

    elder = db.execute(select(User).where(User.invite_code == invite_code)).scalar_one_or_none()
    if elder is None:
        raise HTTPException(status_code=404, detail="Invite code not found")
    if elder.id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot link yourself")

    existing = db.execute(
        select(FamilyLink).where(
            FamilyLink.elder_id == elder.id,
            FamilyLink.caregiver_id == current_user.id,
        )
    ).scalar_one_or_none()
    if existing is not None:
        return _to_link_read(existing)

    link = FamilyLink(
        elder_id=elder.id,
        caregiver_id=current_user.id,
        status="PENDING",
        permissions="VIEW_ONLY",
    )
    db.add(link)
    db.commit()
    db.refresh(link)
    return _to_link_read(link)


@router.get("/requests", response_model=list[FamilyLinkRead])
def list_pending_requests(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    rows = db.execute(
        select(FamilyLink)
        .where(FamilyLink.elder_id == current_user.id, FamilyLink.status == "PENDING")
        .order_by(FamilyLink.id.desc())
    ).scalars().all()
    return [_to_link_read(row) for row in rows]


@router.post("/requests/{link_id}/decision", response_model=FamilyLinkRead)
def decide_link_request(
    link_id: int,
    payload: LinkDecisionPayload,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    row = db.get(FamilyLink, link_id)
    if row is None or row.elder_id != current_user.id:
        raise HTTPException(status_code=404, detail="Request not found")

    row.status = "APPROVED" if payload.approved else "REJECTED"
    db.commit()
    db.refresh(row)
    return _to_link_read(row)


@router.get("/approved-elders", response_model=list[dict])
def list_approved_elders(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    rows = db.execute(
        select(FamilyLink)
        .where(FamilyLink.caregiver_id == current_user.id, FamilyLink.status == "APPROVED")
        .order_by(FamilyLink.id.desc())
    ).scalars().all()
    return [{"elder_id": row.elder_id, "elder_username": row.elder.username} for row in rows]

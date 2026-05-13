from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, joinedload

from app.database import get_db
from app.dependencies import get_current_user, user_has_active_pro
from app.models import ProShare, User

router = APIRouter(prefix="/pro", tags=["pro-share"])

PRO_SHARE_MAX_RECIPIENTS = 5


def try_auto_grant_pro_share_if_eligible(db: Session, caregiver: User, elder: User) -> bool:
    """Silent hook: grant PRO share when caregiver has active PRO and quota allows."""
    if caregiver.id == elder.id:
        return False
    if not user_has_active_pro(caregiver):
        return False
    if db.execute(select(ProShare).where(ProShare.target_user_id == caregiver.id)).scalar_one_or_none():
        return False
    if db.execute(select(ProShare).where(ProShare.target_user_id == elder.id)).scalar_one_or_none():
        return False
    cnt = db.execute(
        select(func.count()).select_from(ProShare).where(ProShare.owner_id == caregiver.id)
    ).scalar_one()
    if cnt >= PRO_SHARE_MAX_RECIPIENTS:
        return False
    db.add(ProShare(owner_id=caregiver.id, target_user_id=elder.id))
    return True


class ProShareAddPayload(BaseModel):
    target_user_id: int


class ProShareSharedUserRead(BaseModel):
    user_id: int
    nickname: str | None
    avatar_url: str | None
    is_proxy: bool


class ProShareMyRead(BaseModel):
    max_shares: int
    used_shares: int
    shared_users: list[ProShareSharedUserRead]


@router.post("/shares", status_code=status.HTTP_201_CREATED)
def add_pro_share(
    payload: ProShareAddPayload,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    if payload.target_user_id == current_user.id:
        raise HTTPException(status_code=400, detail="不能共享给自己")

    if db.execute(select(ProShare).where(ProShare.target_user_id == current_user.id)).scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="共享受益账号无法添加共享人",
        )

    if not user_has_active_pro(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="仅限真实订阅 PRO 的用户添加共享",
        )

    target = db.get(User, payload.target_user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="用户不存在")

    existing_target = db.execute(
        select(ProShare).where(ProShare.target_user_id == payload.target_user_id)
    ).scalar_one_or_none()
    if existing_target is not None:
        raise HTTPException(status_code=400, detail="该用户已被其他账号共享 PRO")

    used = db.execute(
        select(func.count()).select_from(ProShare).where(ProShare.owner_id == current_user.id)
    ).scalar_one()
    if used >= PRO_SHARE_MAX_RECIPIENTS:
        raise HTTPException(status_code=400, detail="共享名额已满（最多 5 人）")

    row = ProShare(owner_id=current_user.id, target_user_id=payload.target_user_id)
    db.add(row)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail="该用户已被其他账号共享 PRO") from None


@router.delete("/shares/{target_user_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_pro_share(
    target_user_id: int,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    row = db.execute(
        select(ProShare).where(
            ProShare.owner_id == current_user.id,
            ProShare.target_user_id == target_user_id,
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(status_code=404, detail="未找到该共享记录")
    db.delete(row)
    db.commit()


@router.get("/shares/my", response_model=ProShareMyRead)
def list_my_pro_shares(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    rows = db.execute(
        select(ProShare)
        .where(ProShare.owner_id == current_user.id)
        .options(joinedload(ProShare.target_user))
        .order_by(ProShare.id.asc())
    ).scalars().all()
    shared_users: list[ProShareSharedUserRead] = []
    for row in rows:
        u = row.target_user
        shared_users.append(
            ProShareSharedUserRead(
                user_id=u.id,
                nickname=u.nickname,
                avatar_url=u.avatar_url,
                is_proxy=bool(u.is_proxy),
            )
        )
    return ProShareMyRead(
        used_shares=len(rows),
        max_shares=PRO_SHARE_MAX_RECIPIENTS,
        shared_users=shared_users,
    )

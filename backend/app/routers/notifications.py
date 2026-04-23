from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models import DeviceToken, User

router = APIRouter(prefix="/notifications", tags=["notifications"])


class DeviceTokenUpsertPayload(BaseModel):
    fcm_token: str | None = None
    wxpusher_uid: str | None = None
    device_label: str | None = None


@router.post("/device-token", response_model=dict)
def upsert_device_token(
    payload: DeviceTokenUpsertPayload,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    token = (payload.fcm_token or "").strip() or None
    wx_uid = (payload.wxpusher_uid or "").strip() or None
    label = (payload.device_label or "").strip() or None

    row = None
    if token:
        row = db.execute(select(DeviceToken).where(DeviceToken.fcm_token == token)).scalar_one_or_none()
    if row is None:
        row = db.execute(
            select(DeviceToken).where(
                DeviceToken.user_id == current_user.id,
                DeviceToken.device_label == label,
            )
        ).scalar_one_or_none()

    if row is None:
        row = DeviceToken(
            user_id=current_user.id,
            fcm_token=token,
            wxpusher_uid=wx_uid,
            device_label=label,
            updated_at=datetime.utcnow(),
        )
        db.add(row)
    else:
        row.user_id = current_user.id
        row.fcm_token = token or row.fcm_token
        row.wxpusher_uid = wx_uid if wx_uid is not None else row.wxpusher_uid
        row.device_label = label if label is not None else row.device_label
        row.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(row)
    return {"id": row.id, "user_id": row.user_id, "bound": True}

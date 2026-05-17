import logging
from typing import Annotated
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_pro_status
from app.models import MedicationPlan, User
from app.routers.medications import _resolve_manage_target_user_id
from app.schema_bootstrap import ensure_medication_voice_url_column, ensure_user_profile_columns
from app.schemas.medication import VoiceUploadUrlResponse, VoiceUrlUpdate
from app.services.r2_service import (
    PRESIGN_EXPIRES_SECONDS,
    VOICE_CONTENT_TYPE,
    create_family_voice_presigned_put,
    r2_configured,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/reminders", tags=["reminders"])


def _validate_public_voice_url(voice_url: str) -> None:
    parsed = urlparse(voice_url.strip())
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise HTTPException(status_code=400, detail="Invalid voice_url")


def _assert_can_manage_elder_voice(
    db: Session, current_user: User, elder_user_id: int
) -> User:
    elder = db.get(User, elder_user_id)
    if elder is None:
        raise HTTPException(status_code=404, detail="User not found")
    if elder_user_id == current_user.id:
        return elder
    _resolve_manage_target_user_id(db, current_user, elder_user_id)
    return elder


def _apply_family_voice_to_user(db: Session, elder: User, voice_url: str) -> None:
    url = voice_url.strip()
    elder.family_voice_url = url
    db.execute(
        update(MedicationPlan)
        .where(
            MedicationPlan.user_id == elder.id,
            MedicationPlan.is_active.is_(True),
        )
        .values(voice_url=url)
    )


@router.get("/voice-upload-url", response_model=VoiceUploadUrlResponse)
def get_voice_upload_url(
    user_id: Annotated[int, Query(ge=1)],
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(require_pro_status)],
    plan_id: Annotated[int | None, Query(ge=1)] = None,
):
    """Presigned PUT for one shared family voice per elder (PRO). plan_id is ignored."""
    ensure_user_profile_columns(db)
    if not r2_configured():
        raise HTTPException(status_code=503, detail="Voice upload is not configured")

    _assert_can_manage_elder_voice(db, current_user, user_id)

    try:
        upload_url, _key, public_url = create_family_voice_presigned_put(user_id=user_id)
    except RuntimeError as exc:
        logger.exception("reminders: presign failed user_id=%s: %s", user_id, exc)
        raise HTTPException(status_code=503, detail="Failed to create upload URL") from exc

    return VoiceUploadUrlResponse(
        upload_url=upload_url,
        voice_url=public_url,
        content_type=VOICE_CONTENT_TYPE,
        expires_in=PRESIGN_EXPIRES_SECONDS,
    )


@router.patch("/user/{user_id}/voice", response_model=dict)
def bind_user_family_voice_url(
    user_id: int,
    payload: VoiceUrlUpdate,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(require_pro_status)],
):
    ensure_user_profile_columns(db)
    ensure_medication_voice_url_column(db)
    _validate_public_voice_url(payload.voice_url)

    if payload.user_id is not None and payload.user_id != user_id:
        raise HTTPException(status_code=400, detail="user_id mismatch")

    elder = _assert_can_manage_elder_voice(db, current_user, user_id)
    _apply_family_voice_to_user(db, elder, payload.voice_url)
    try:
        db.commit()
        db.refresh(elder)
    except Exception as exc:
        db.rollback()
        logger.exception("reminders: bind family voice failed user_id=%s: %s", user_id, exc)
        raise HTTPException(status_code=500, detail="Failed to save voice URL") from exc
    return {"ok": True, "user_id": elder.id, "voice_url": elder.family_voice_url}


@router.patch("/{plan_id}/voice", response_model=dict)
def bind_plan_voice_url_legacy(
    plan_id: int,
    payload: VoiceUrlUpdate,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(require_pro_status)],
):
    """Legacy route: writes shared family voice for the plan owner."""
    ensure_user_profile_columns(db)
    ensure_medication_voice_url_column(db)
    _validate_public_voice_url(payload.voice_url)

    plan = db.get(MedicationPlan, plan_id)
    if plan is None or not plan.is_active:
        raise HTTPException(status_code=404, detail="Plan not found")

    elder_user_id = payload.user_id if payload.user_id is not None else plan.user_id
    if plan.user_id != elder_user_id:
        raise HTTPException(status_code=400, detail="user_id does not match plan owner")

    elder = _assert_can_manage_elder_voice(db, current_user, elder_user_id)
    _apply_family_voice_to_user(db, elder, payload.voice_url)
    try:
        db.commit()
        db.refresh(elder)
    except Exception as exc:
        db.rollback()
        logger.exception("reminders: bind voice legacy plan_id=%s: %s", plan_id, exc)
        raise HTTPException(status_code=500, detail="Failed to save voice URL") from exc
    return {"ok": True, "user_id": elder.id, "voice_url": elder.family_voice_url}

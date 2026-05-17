import logging
from typing import Annotated
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import require_pro_status
from app.models import MedicationPlan, User
from app.routers.medications import _resolve_manage_target_user_id
from app.schema_bootstrap import ensure_medication_voice_url_column
from app.schemas.medication import VoiceUploadUrlResponse, VoiceUrlUpdate
from app.services.r2_service import (
    PRESIGN_EXPIRES_SECONDS,
    VOICE_CONTENT_TYPE,
    create_voice_presigned_put,
    r2_configured,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/reminders", tags=["reminders"])


def _validate_public_voice_url(voice_url: str) -> None:
    parsed = urlparse(voice_url.strip())
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise HTTPException(status_code=400, detail="Invalid voice_url")


@router.get("/voice-upload-url", response_model=VoiceUploadUrlResponse)
def get_voice_upload_url(
    plan_id: Annotated[int, Query(ge=1)],
    user_id: Annotated[int, Query(ge=1)],
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(require_pro_status)],
):
    """Presigned PUT for caregiver-recorded family voice (PRO)."""
    ensure_medication_voice_url_column(db)
    if not r2_configured():
        raise HTTPException(status_code=503, detail="Voice upload is not configured")

    plan = db.get(MedicationPlan, plan_id)
    if plan is None or not plan.is_active:
        raise HTTPException(status_code=404, detail="Plan not found")
    if plan.user_id != user_id:
        raise HTTPException(status_code=400, detail="user_id does not match plan owner")

    if user_id == current_user.id:
        managed_user_id = current_user.id
    else:
        managed_user_id = _resolve_manage_target_user_id(db, current_user, user_id)
        if managed_user_id != user_id:
            raise HTTPException(status_code=403, detail="No permission to manage this plan")

    try:
        upload_url, _key, public_url = create_voice_presigned_put(
            user_id=user_id,
            plan_id=plan_id,
        )
    except RuntimeError as exc:
        logger.exception("reminders: presign failed plan_id=%s: %s", plan_id, exc)
        raise HTTPException(status_code=503, detail="Failed to create upload URL") from exc

    return VoiceUploadUrlResponse(
        upload_url=upload_url,
        voice_url=public_url,
        content_type=VOICE_CONTENT_TYPE,
        expires_in=PRESIGN_EXPIRES_SECONDS,
    )


@router.patch("/{plan_id}/voice", response_model=dict)
def bind_plan_voice_url(
    plan_id: int,
    payload: VoiceUrlUpdate,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(require_pro_status)],
):
    ensure_medication_voice_url_column(db)
    _validate_public_voice_url(payload.voice_url)

    plan = db.get(MedicationPlan, plan_id)
    if plan is None or not plan.is_active:
        raise HTTPException(status_code=404, detail="Plan not found")

    target_user_id = payload.user_id if payload.user_id is not None else plan.user_id
    if plan.user_id != target_user_id:
        raise HTTPException(status_code=400, detail="user_id does not match plan owner")

    if target_user_id == current_user.id:
        if plan.user_id != current_user.id:
            raise HTTPException(status_code=403, detail="No permission to update this plan")
    else:
        _resolve_manage_target_user_id(db, current_user, target_user_id)

    plan.voice_url = payload.voice_url.strip()
    try:
        db.commit()
        db.refresh(plan)
    except Exception as exc:
        db.rollback()
        logger.exception("reminders: bind voice_url failed plan_id=%s: %s", plan_id, exc)
        raise HTTPException(status_code=500, detail="Failed to save voice URL") from exc
    return {"ok": True, "plan_id": plan.id, "voice_url": plan.voice_url}

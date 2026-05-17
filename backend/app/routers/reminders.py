import logging
from typing import Annotated
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, require_pro_status
from app.models import FamilyLink, MedicationPlan, User
from app.routers.medications import _resolve_manage_target_user_id, _resolve_target_user_id
from app.schema_bootstrap import (
    ensure_family_link_voice_columns,
    ensure_medication_voice_url_column,
    ensure_user_profile_columns,
)
from app.schemas.medication import VoiceDownloadUrlResponse, VoiceUploadUrlResponse, VoiceUrlUpdate
from app.services.family_voice_service import (
    apply_voice_to_link,
    get_approved_link,
    resolve_voice_for_pair,
)
from app.services.r2_service import (
    PRESIGN_EXPIRES_SECONDS,
    PRESIGN_GET_EXPIRES_SECONDS,
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


def _require_caregiver_link(
    db: Session, current_user: User, elder_user_id: int
) -> FamilyLink:
    if elder_user_id == current_user.id:
        raise HTTPException(
            status_code=400,
            detail="Record family voice from a caregiver account for this elder",
        )
    link = get_approved_link(
        db, caregiver_id=current_user.id, elder_id=elder_user_id
    )
    if link is None:
        raise HTTPException(
            status_code=403,
            detail="Only an approved caregiver can manage family voice for this elder",
        )
    return link


def _apply_family_voice_to_link_and_plans(
    db: Session, link: FamilyLink, voice_url: str
) -> None:
    url = voice_url.strip()
    apply_voice_to_link(link, url)
    elder = link.elder
    if elder is not None:
        elder.family_voice_url = url
    db.execute(
        update(MedicationPlan)
        .where(
            MedicationPlan.user_id == link.elder_id,
            MedicationPlan.is_active.is_(True),
        )
        .values(voice_url=url)
    )


@router.get("/voice-download-url", response_model=VoiceDownloadUrlResponse)
def get_voice_download_url(
    user_id: Annotated[int, Query(ge=1)],
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    caregiver_id: Annotated[int | None, Query(ge=1)] = None,
):
    """Presigned GET for elder device. Optional caregiver_id selects that link's voice."""
    ensure_user_profile_columns(db)
    ensure_family_link_voice_columns(db)
    if not r2_configured():
        raise HTTPException(status_code=503, detail="Voice download is not configured")

    target = user_id if user_id != current_user.id else None
    elder_id = _resolve_target_user_id(db, current_user, target)

    resolved_caregiver_id = caregiver_id
    if resolved_caregiver_id is None and current_user.id != elder_id:
        link = get_approved_link(
            db, caregiver_id=current_user.id, elder_id=elder_id
        )
        if link is not None and (link.family_voice_url or "").strip():
            resolved_caregiver_id = current_user.id

    if resolved_caregiver_id is None:
        from app.services.family_voice_service import resolve_latest_elder_voice

        download_url, _ = resolve_latest_elder_voice(db, elder_id)
    else:
        download_url = resolve_voice_for_pair(
            db, caregiver_id=resolved_caregiver_id, elder_id=elder_id
        )

    if not download_url:
        raise HTTPException(status_code=404, detail="No family voice configured")
    return VoiceDownloadUrlResponse(
        download_url=download_url,
        expires_in=PRESIGN_GET_EXPIRES_SECONDS,
    )


@router.get("/voice-upload-url", response_model=VoiceUploadUrlResponse)
def get_voice_upload_url(
    user_id: Annotated[int, Query(ge=1)],
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(require_pro_status)],
    plan_id: Annotated[int | None, Query(ge=1)] = None,
):
    """Presigned PUT: voice/{caregiver_id}/{elder_id}_{timestamp}_family_voice.m4a."""
    ensure_user_profile_columns(db)
    ensure_family_link_voice_columns(db)
    if not r2_configured():
        raise HTTPException(status_code=503, detail="Voice upload is not configured")

    elder_user_id = user_id
    _assert_can_manage_elder_voice(db, current_user, elder_user_id)
    _require_caregiver_link(db, current_user, elder_user_id)

    if plan_id is not None:
        logger.debug("reminders: plan_id=%s ignored for family voice upload", plan_id)

    try:
        upload_url, _key, public_url = create_family_voice_presigned_put(
            caregiver_id=current_user.id,
            elder_id=elder_user_id,
        )
    except RuntimeError as exc:
        logger.exception(
            "reminders: presign failed caregiver=%s elder=%s: %s",
            current_user.id,
            elder_user_id,
            exc,
        )
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
    ensure_family_link_voice_columns(db)
    ensure_medication_voice_url_column(db)
    _validate_public_voice_url(payload.voice_url)

    if payload.user_id is not None and payload.user_id != user_id:
        raise HTTPException(status_code=400, detail="user_id mismatch")

    _assert_can_manage_elder_voice(db, current_user, user_id)
    link = _require_caregiver_link(db, current_user, user_id)
    _apply_family_voice_to_link_and_plans(db, link, payload.voice_url)
    try:
        db.commit()
        db.refresh(link)
    except Exception as exc:
        db.rollback()
        logger.exception("reminders: bind family voice failed user_id=%s: %s", user_id, exc)
        raise HTTPException(status_code=500, detail="Failed to save voice URL") from exc
    return {
        "ok": True,
        "user_id": user_id,
        "caregiver_id": current_user.id,
        "voice_url": link.family_voice_url,
    }


@router.patch("/{plan_id}/voice", response_model=dict)
def bind_plan_voice_url_legacy(
    plan_id: int,
    payload: VoiceUrlUpdate,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(require_pro_status)],
):
    """Legacy route: binds caregiver ↔ elder family voice for the plan owner."""
    ensure_user_profile_columns(db)
    ensure_family_link_voice_columns(db)
    ensure_medication_voice_url_column(db)
    _validate_public_voice_url(payload.voice_url)

    plan = db.get(MedicationPlan, plan_id)
    if plan is None or not plan.is_active:
        raise HTTPException(status_code=404, detail="Plan not found")

    elder_user_id = payload.user_id if payload.user_id is not None else plan.user_id
    if plan.user_id != elder_user_id:
        raise HTTPException(status_code=400, detail="user_id does not match plan owner")

    _assert_can_manage_elder_voice(db, current_user, elder_user_id)
    link = _require_caregiver_link(db, current_user, elder_user_id)
    _apply_family_voice_to_link_and_plans(db, link, payload.voice_url)
    try:
        db.commit()
        db.refresh(link)
    except Exception as exc:
        db.rollback()
        logger.exception("reminders: bind voice legacy plan_id=%s: %s", plan_id, exc)
        raise HTTPException(status_code=500, detail="Failed to save voice URL") from exc
    return {
        "ok": True,
        "user_id": elder_user_id,
        "caregiver_id": current_user.id,
        "voice_url": link.family_voice_url,
    }

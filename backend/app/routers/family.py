import secrets
import string
import uuid
import logging
from typing import Annotated
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException, status
from redis import Redis
from sqlalchemy import inspect, select, text
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.dependencies import get_current_user, user_has_active_pro
from app.models import FamilyLink, FamilyLinkActionLog, ProShare, User
from app.orm_loads import family_link_with_users
from app.schemas.family import (
    ApprovedFamilyMemberResponse,
    FamilyLinkResponse,
    InviteCodeResponse,
    LinkApplyRequest,
    LinkDecisionRequest,
    QrTokenResponse,
    ResetElderPasswordRequest,
    ScanQrRequest,
    ScanQrResponse,
    WeeklyReportToggleRequest,
)
from app.schemas.mappers import approved_member_to_response, family_link_to_response
from app.security import hash_password

router = APIRouter(prefix="/family", tags=["family"])
_QR_TOKEN_EXPIRES_SECONDS = 180
_QR_TOKEN_KEY_PREFIX = "family:qr-token:"
logger = logging.getLogger(__name__)


def _record_family_action(
    db: Session,
    *,
    action: str,
    actor_user_id: int,
    elder_id: int | None = None,
    caregiver_id: int | None = None,
    link_id: int | None = None,
    counterpart_name: str | None = None,
    invite_code: str | None = None,
) -> None:
    log = FamilyLinkActionLog(
        action=action,
        actor_user_id=actor_user_id,
        elder_id=elder_id,
        caregiver_id=caregiver_id,
        link_id=link_id,
        counterpart_name=counterpart_name,
        invite_code=invite_code,
    )
    db.add(log)
    db.commit()


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


def _ensure_family_link_schema(db: Session) -> None:
    columns = {col["name"] for col in inspect(db.bind).get_columns("family_links")}
    if "elder_alias" not in columns:
        db.execute(text("ALTER TABLE family_links ADD COLUMN elder_alias VARCHAR(128)"))
        db.commit()
    if "caregiver_alias" not in columns:
        db.execute(text("ALTER TABLE family_links ADD COLUMN caregiver_alias VARCHAR(128)"))
        db.commit()
    if "receive_weekly_report" not in columns:
        db.execute(text("ALTER TABLE family_links ADD COLUMN receive_weekly_report BOOLEAN DEFAULT TRUE"))
        db.commit()
        db.execute(text("UPDATE family_links SET receive_weekly_report = TRUE WHERE receive_weekly_report IS NULL"))
        db.commit()


def _redis_client() -> Redis:
    redis_url = settings.redis_url.strip()
    common_kwargs = {
        "decode_responses": True,
        "socket_connect_timeout": 3,
        "socket_timeout": 3,
    }
    if redis_url.startswith("rediss://"):
        return Redis.from_url(
            redis_url,
            ssl_cert_reqs=None,
            **common_kwargs,
        )
    return Redis.from_url(redis_url, **common_kwargs)


def _redis_url_prefix(redis_url: str) -> str:
    parsed = urlparse(redis_url.strip())
    if not parsed.scheme:
        return "unknown://"
    host = parsed.hostname or "unknown-host"
    port = parsed.port or ""
    suffix = f":{port}" if port else ""
    return f"{parsed.scheme}://{host}{suffix}"


def _fallback_redis_url(redis_url: str) -> str | None:
    parsed = urlparse(redis_url.strip())
    if parsed.scheme not in {"redis", "rediss"}:
        return None
    host = (parsed.hostname or "").strip().lower()
    port = parsed.port
    if host != "redis" or port in (None, 6379):
        return None
    netloc = "redis:6379"
    if parsed.username:
        auth = parsed.username
        if parsed.password:
            auth = f"{auth}:{parsed.password}"
        netloc = f"{auth}@{netloc}"
    return parsed._replace(netloc=netloc).geturl()


def _pro_share_owner_by_elder(db: Session, elder_ids: list[int]) -> dict[int, int]:
    if not elder_ids:
        return {}
    try:
        rows = db.execute(
            select(ProShare.target_user_id, ProShare.owner_id).where(
                ProShare.target_user_id.in_(elder_ids)
            )
        ).all()
        return {int(target_id): int(owner_id) for target_id, owner_id in rows}
    except Exception as exc:
        logger.warning("family: batch ProShare lookup failed: %s", exc)
        return {}


def _get_family_link(db: Session, link_id: int) -> FamilyLink | None:
    return db.execute(
        select(FamilyLink).where(FamilyLink.id == link_id).options(*family_link_with_users())
    ).scalar_one_or_none()


@router.get("/invite-code", response_model=InviteCodeResponse)
def get_invite_code(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    code = _get_or_create_invite_code(db, current_user)
    return InviteCodeResponse(invite_code=code)


@router.get("/qr-token", response_model=QrTokenResponse)
def get_qr_token(
    current_user: Annotated[User, Depends(get_current_user)],
):
    token = str(uuid.uuid4())
    key = f"{_QR_TOKEN_KEY_PREFIX}{token}"
    redis_url = settings.redis_url.strip()
    fallback_url = _fallback_redis_url(redis_url)
    try:
        client = _redis_client()
        client.setex(key, _QR_TOKEN_EXPIRES_SECONDS, str(current_user.id))
    except Exception as exc:
        if fallback_url is not None:
            try:
                logger.warning(
                    "family.qr_token_retry redis_prefix=%s fallback_prefix=%s error_type=%s",
                    _redis_url_prefix(redis_url),
                    _redis_url_prefix(fallback_url),
                    exc.__class__.__name__,
                )
                fallback_client = Redis.from_url(
                    fallback_url,
                    decode_responses=True,
                    socket_connect_timeout=3,
                    socket_timeout=3,
                )
                fallback_client.setex(key, _QR_TOKEN_EXPIRES_SECONDS, str(current_user.id))
                return QrTokenResponse(
                    qr_payload=f"zellia://bind?token={token}",
                    expires_in=_QR_TOKEN_EXPIRES_SECONDS,
                )
            except Exception as fallback_exc:
                logger.exception(
                    "family.qr_token_fallback_failed redis_prefix=%s fallback_prefix=%s error_type=%s",
                    _redis_url_prefix(redis_url),
                    _redis_url_prefix(fallback_url),
                    fallback_exc.__class__.__name__,
                )
        logger.exception(
            "family.qr_token_failed redis_prefix=%s error_type=%s",
            _redis_url_prefix(settings.redis_url),
            exc.__class__.__name__,
        )
        raise HTTPException(status_code=503, detail="二维码服务暂时不可用") from exc
    return QrTokenResponse(
        qr_payload=f"zellia://bind?token={token}",
        expires_in=_QR_TOKEN_EXPIRES_SECONDS,
    )


@router.post("/scan-qr", response_model=ScanQrResponse)
def scan_qr_bind(
    payload: ScanQrRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_family_link_schema(db)
    token = payload.token.strip()
    family_alias = (payload.family_alias or "").strip() or None
    if not token:
        raise HTTPException(status_code=400, detail="Token is required")

    key = f"{_QR_TOKEN_KEY_PREFIX}{token}"
    redis_url = settings.redis_url.strip()
    fallback_url = _fallback_redis_url(redis_url)
    try:
        client = _redis_client()
        elder_id_raw = client.get(key)
        if elder_id_raw is None:
            raise HTTPException(status_code=400, detail="二维码已失效")
        client.delete(key)
    except HTTPException:
        raise
    except Exception as exc:
        if fallback_url is not None:
            try:
                logger.warning(
                    "family.scan_qr_retry redis_prefix=%s fallback_prefix=%s error_type=%s",
                    _redis_url_prefix(redis_url),
                    _redis_url_prefix(fallback_url),
                    exc.__class__.__name__,
                )
                fallback_client = Redis.from_url(
                    fallback_url,
                    decode_responses=True,
                    socket_connect_timeout=3,
                    socket_timeout=3,
                )
                elder_id_raw = fallback_client.get(key)
                if elder_id_raw is None:
                    raise HTTPException(status_code=400, detail="二维码已失效")
                fallback_client.delete(key)
            except HTTPException:
                raise
            except Exception as fallback_exc:
                logger.exception(
                    "family.scan_qr_fallback_failed redis_prefix=%s fallback_prefix=%s error_type=%s",
                    _redis_url_prefix(redis_url),
                    _redis_url_prefix(fallback_url),
                    fallback_exc.__class__.__name__,
                )
                raise HTTPException(status_code=503, detail="二维码服务暂时不可用") from fallback_exc
        else:
            logger.exception(
                "family.scan_qr_failed redis_prefix=%s error_type=%s",
                _redis_url_prefix(settings.redis_url),
                exc.__class__.__name__,
            )
            raise HTTPException(status_code=503, detail="二维码服务暂时不可用") from exc
    if elder_id_raw is None:
        raise HTTPException(status_code=400, detail="二维码已失效")
    if isinstance(elder_id_raw, bytes):
        elder_id_raw = elder_id_raw.decode("utf-8", errors="ignore")
    if not str(elder_id_raw).strip():
        raise HTTPException(status_code=400, detail="二维码已失效")
    elder_id = int(elder_id_raw)
    if elder_id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot bind yourself")

    elder = db.get(User, elder_id)
    if elder is None:
        raise HTTPException(status_code=404, detail="Elder not found")

    existing = db.execute(
        select(FamilyLink).where(
            FamilyLink.elder_id == elder_id,
            FamilyLink.caregiver_id == current_user.id,
        )
    ).scalar_one_or_none()
    if existing is not None:
        if family_alias:
            existing.elder_alias = family_alias
            db.commit()
            db.refresh(existing)
        _record_family_action(
            db,
            action="bind_scan_submitted",
            actor_user_id=current_user.id,
            elder_id=existing.elder_id,
            caregiver_id=existing.caregiver_id,
            link_id=existing.id,
            counterpart_name=family_alias,
        )
        return ScanQrResponse(
            success=True,
            link_id=existing.id,
            status=existing.status,
            elder_id=elder.id,
            elder_username=elder.username,
            elder_nickname=elder.nickname,
        )

    link = FamilyLink(
        elder_id=elder_id,
        caregiver_id=current_user.id,
        status="PENDING",
        permissions="VIEW_ONLY",
        elder_alias=family_alias,
    )
    db.add(link)
    db.commit()
    db.refresh(link)
    _record_family_action(
        db,
        action="bind_scan_submitted",
        actor_user_id=current_user.id,
        elder_id=link.elder_id,
        caregiver_id=link.caregiver_id,
        link_id=link.id,
        counterpart_name=family_alias,
    )
    return ScanQrResponse(
        success=True,
        link_id=link.id,
        status=link.status,
        elder_id=elder.id,
        elder_username=elder.username,
        elder_nickname=elder.nickname,
    )


@router.post("/apply", response_model=FamilyLinkResponse, status_code=status.HTTP_201_CREATED)
def apply_by_invite_code(
    payload: LinkApplyRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_family_schema(db)
    _ensure_family_link_schema(db)
    invite_code = payload.invite_code.strip().upper()
    elder_alias = (payload.elder_alias or "").strip() or None
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
        if elder_alias:
            existing.elder_alias = elder_alias
            db.commit()
            db.refresh(existing)
        _record_family_action(
            db,
            action="bind_apply_submitted",
            actor_user_id=current_user.id,
            elder_id=existing.elder_id,
            caregiver_id=existing.caregiver_id,
            link_id=existing.id,
            counterpart_name=elder_alias,
            invite_code=invite_code,
        )
        loaded = _get_family_link(db, existing.id)
        if loaded is None:
            raise HTTPException(status_code=500, detail="Link not found")
        return family_link_to_response(loaded)

    link = FamilyLink(
        elder_id=elder.id,
        caregiver_id=current_user.id,
        status="PENDING",
        permissions="VIEW_ONLY",
        elder_alias=elder_alias,
    )
    db.add(link)
    db.commit()
    loaded = _get_family_link(db, link.id)
    if loaded is None:
        raise HTTPException(status_code=500, detail="Link not found after create")
    _record_family_action(
        db,
        action="bind_apply_submitted",
        actor_user_id=current_user.id,
        elder_id=loaded.elder_id,
        caregiver_id=loaded.caregiver_id,
        link_id=loaded.id,
        counterpart_name=elder_alias,
        invite_code=invite_code,
    )
    return family_link_to_response(loaded)


@router.get("/requests", response_model=list[FamilyLinkResponse])
def list_pending_requests(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_family_link_schema(db)
    rows = db.execute(
        select(FamilyLink)
        .where(FamilyLink.elder_id == current_user.id, FamilyLink.status == "PENDING")
        .options(*family_link_with_users())
        .order_by(FamilyLink.id.desc())
    ).scalars().all()
    return [family_link_to_response(row) for row in rows]


@router.post("/requests/{link_id}/decision", response_model=FamilyLinkResponse)
def decide_link_request(
    link_id: int,
    payload: LinkDecisionRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_family_link_schema(db)
    row = _get_family_link(db, link_id)
    if row is None or row.elder_id != current_user.id:
        raise HTTPException(status_code=404, detail="Request not found")

    row.status = "APPROVED" if payload.approved else "REJECTED"
    if payload.approved:
        row.permissions = "MANAGE"
        alias = (payload.caregiver_alias or "").strip()
        row.caregiver_alias = alias or row.caregiver_alias
    else:
        row.permissions = "VIEW_ONLY"
        row.caregiver_alias = None
    db.commit()
    _record_family_action(
        db,
        action="bind_approved" if payload.approved else "bind_rejected",
        actor_user_id=current_user.id,
        elder_id=row.elder_id,
        caregiver_id=row.caregiver_id,
        link_id=row.id,
    )
    row = _get_family_link(db, link_id)
    if row is None:
        raise HTTPException(status_code=500, detail="Link not found after update")
    return family_link_to_response(row)


@router.get("/approved-elders", response_model=list[ApprovedFamilyMemberResponse])
def list_approved_elders(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_family_link_schema(db)
    rows = db.execute(
        select(FamilyLink)
        .where(FamilyLink.caregiver_id == current_user.id, FamilyLink.status == "APPROVED")
        .options(*family_link_with_users())
        .order_by(FamilyLink.id.desc())
    ).scalars().all()
    lock_map = _pro_share_owner_by_elder(db, [row.elder_id for row in rows])
    out: list[ApprovedFamilyMemberResponse] = []
    for row in rows:
        owner_id = lock_map.get(row.elder_id)
        locked_other = owner_id is not None and owner_id != current_user.id
        out.append(
            approved_member_to_response(
                row,
                elder_has_active_pro=user_has_active_pro(row.elder),
                elder_pro_share_locked_other=locked_other,
            )
        )
    return out


@router.get("/guardians", response_model=list[ApprovedFamilyMemberResponse])
def list_guardians(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_family_link_schema(db)
    rows = db.execute(
        select(FamilyLink)
        .where(FamilyLink.elder_id == current_user.id, FamilyLink.status == "APPROVED")
        .options(*family_link_with_users())
        .order_by(FamilyLink.id.desc())
    ).scalars().all()
    return [
        approved_member_to_response(
            row,
            elder_has_active_pro=user_has_active_pro(row.elder),
            elder_pro_share_locked_other=False,
        )
        for row in rows
    ]


@router.get("/approved-caregivers", response_model=list[ApprovedFamilyMemberResponse], include_in_schema=False)
def list_approved_caregivers_compat(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    return list_guardians(db=db, current_user=current_user)


@router.delete("/unbind/{link_id}", status_code=status.HTTP_204_NO_CONTENT)
def unbind_family_link(
    link_id: int,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_family_link_schema(db)
    row = _get_family_link(db, link_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Link not found")
    if current_user.id not in (row.elder_id, row.caregiver_id):
        raise HTTPException(status_code=403, detail="No permission to unbind this link")
    _record_family_action(
        db,
        action="unbind_success",
        actor_user_id=current_user.id,
        elder_id=row.elder_id,
        caregiver_id=row.caregiver_id,
        link_id=row.id,
    )
    db.delete(row)
    db.commit()


@router.put("/links/{link_id}/weekly-report", response_model=ApprovedFamilyMemberResponse)
def toggle_weekly_report_subscription(
    link_id: int,
    payload: WeeklyReportToggleRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_family_link_schema(db)
    row = _get_family_link(db, link_id)
    if row is None:
        raise HTTPException(status_code=404, detail="Link not found")
    if row.caregiver_id != current_user.id:
        raise HTTPException(status_code=403, detail="No permission to update weekly report setting")
    row.receive_weekly_report = payload.receive_weekly_report
    db.commit()
    row = _get_family_link(db, link_id)
    if row is None:
        raise HTTPException(status_code=500, detail="Link not found after update")
    lock_map = _pro_share_owner_by_elder(db, [row.elder_id])
    owner_id = lock_map.get(row.elder_id)
    locked_other = owner_id is not None and owner_id != current_user.id
    return approved_member_to_response(
        row,
        elder_has_active_pro=user_has_active_pro(row.elder),
        elder_pro_share_locked_other=locked_other,
    )


@router.post("/reset-elder-password")
def reset_elder_password(
    payload: ResetElderPasswordRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_family_link_schema(db)
    link = db.execute(
        select(FamilyLink).where(
            FamilyLink.caregiver_id == current_user.id,
            FamilyLink.elder_id == payload.elder_id,
            FamilyLink.status == "APPROVED",
        )
    ).scalar_one_or_none()
    if link is None:
        raise HTTPException(status_code=403, detail="No approved relation with this elder")
    elder = db.get(User, payload.elder_id)
    if elder is None:
        raise HTTPException(status_code=404, detail="Elder not found")
    temp_password = payload.temp_password.strip()
    if len(temp_password) < 6:
        raise HTTPException(status_code=400, detail="Temporary password must be at least 6 characters")
    elder.hashed_password = hash_password(temp_password)
    elder.is_active = True
    db.commit()
    return {"message": "Password reset successfully"}

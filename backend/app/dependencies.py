from datetime import datetime, timezone
from typing import Annotated
import json
import base64
import secrets
import string

import firebase_admin
from firebase_admin import auth as firebase_auth
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from app.config import settings
from app.database import get_db
from app.firebase_app import ensure_firebase_app_ready
from app.models import ProShare, User
from app.schema_bootstrap import ensure_user_profile_columns
from app.security import decode_token, hash_password

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")

# Re-export for legacy imports (webhooks).
_ensure_user_profile_columns = ensure_user_profile_columns


def user_has_active_pro(user: User | None) -> bool:
    if user is None or not bool(getattr(user, "is_premium", False)):
        return False
    expires_at = getattr(user, "premium_expires_at", None)
    if expires_at is None:
        return False
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    return expires_at > datetime.now(timezone.utc)


def resolve_profile_pro_display(
    db: Session, user: User
) -> tuple[bool, datetime | None, bool]:
    """Returns (effective PRO access, expiry shown in profile, share-only recipient)."""
    own = user_has_active_pro(user)
    row = (
        db.execute(
            select(ProShare)
            .where(ProShare.target_user_id == user.id)
            .options(joinedload(ProShare.owner))
        )
        .unique()
        .scalar_one_or_none()
    )
    shared_active = False
    if row is not None and row.owner is not None:
        shared_active = user_has_active_pro(row.owner)
    if own:
        display_expires = getattr(user, "premium_expires_at", None)
    elif shared_active and row is not None and row.owner is not None:
        display_expires = getattr(row.owner, "premium_expires_at", None)
    else:
        display_expires = None
    effective = own or shared_active
    share_only = shared_active and not own
    return effective, display_expires, share_only


def get_current_user(
    token: Annotated[str, Depends(oauth2_scheme)],
    db: Annotated[Session, Depends(get_db)],
) -> User:
    _ensure_user_profile_columns(db)
    user = _resolve_user_from_firebase_token(db, token)
    if user is None:
        username = decode_token(token)
        if username is not None:
            user = db.query(User).filter(User.username == username).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


def _extract_project_id_from_id_token(id_token: str) -> str | None:
    try:
        parts = id_token.split(".")
        if len(parts) < 2:
            return None
        payload = parts[1]
        payload += "=" * ((4 - len(payload) % 4) % 4)
        decoded = base64.urlsafe_b64decode(payload.encode("utf-8")).decode("utf-8")
        claims = json.loads(decoded)
        aud = claims.get("aud")
        if isinstance(aud, str) and aud.strip():
            return aud.strip()
        return None
    except Exception:
        return None


def _verify_firebase_token_with_google(token: str, project_id: str) -> dict:
    req = google_requests.Request()
    claims = google_id_token.verify_firebase_token(token, req, audience=project_id)
    if not isinstance(claims, dict):
        raise ValueError("Invalid Firebase token claims")
    return claims


def _create_unique_firebase_username(db: Session) -> str:
    prefix = "f_"
    alphabet = string.ascii_lowercase + string.digits
    for _ in range(50):
        suffix = "".join(secrets.choice(alphabet) for _ in range(10))
        username = f"{prefix}{suffix}"
        exists = db.execute(select(User.id).where(User.username == username)).first()
        if exists is None:
            return username
    raise HTTPException(status_code=500, detail="Failed to generate firebase username")


def _resolve_user_from_firebase_token(db: Session, token: str) -> User | None:
    token_project_id = _extract_project_id_from_id_token(token)
    firebase_ready = ensure_firebase_app_ready(fallback_project_id=token_project_id)
    if not firebase_ready and not token_project_id:
        return None
    try:
        if firebase_ready:
            claims = firebase_auth.verify_id_token(token)
        else:
            claims = _verify_firebase_token_with_google(token, token_project_id)
    except Exception:
        if not token_project_id:
            return None
        try:
            claims = _verify_firebase_token_with_google(token, token_project_id)
        except Exception:
            return None

    email = (claims.get("email") or "").strip().lower()
    firebase_uid = (claims.get("user_id") or claims.get("uid") or "").strip()
    display_name = (claims.get("name") or "").strip()

    user = None
    if email:
        user = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    if user is None and firebase_uid:
        user = db.execute(select(User).where(User.username == firebase_uid)).scalar_one_or_none()
    if user is None:
        nickname = display_name or (email.split("@")[0] if email else "firebase_user")
        user = User(
            username=firebase_uid if firebase_uid and len(firebase_uid) <= 20 else _create_unique_firebase_username(db),
            hashed_password=hash_password(secrets.token_urlsafe(32)),
            email=email or None,
            nickname=nickname[:128],
            is_active=True,
            is_proxy=False,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
    elif not user.is_active:
        user.is_active = True
        db.commit()
        db.refresh(user)
    return user


def require_pro_user(
    current_user: Annotated[User, Depends(get_current_user)],
) -> User:
    if not user_has_active_pro(current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="此功能仅限 PRO 用户使用",
        )
    return current_user


async def resolve_user_pro_status(user_id: int, db: Session) -> bool:
    user = db.get(User, user_id)
    if user is None:
        return False
    if bool(user.is_premium):
        return True
    row = (
        db.execute(
            select(ProShare)
            .where(ProShare.target_user_id == user_id)
            .options(joinedload(ProShare.owner))
        )
        .unique()
        .scalar_one_or_none()
    )
    if row is None or row.owner is None:
        return False
    return bool(row.owner.is_premium)


async def require_pro_status(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[Session, Depends(get_db)],
) -> User:
    if not await resolve_user_pro_status(current_user.id, db):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="此功能仅限 PRO 订阅或共享用户使用",
        )
    return current_user

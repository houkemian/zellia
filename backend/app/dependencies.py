from datetime import datetime, timezone
from typing import Annotated
import os
import json
import base64
import secrets
import string

import firebase_admin
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import inspect, select, text
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.models import User
from app.security import decode_token, hash_password

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def _ensure_user_profile_columns(db: Session) -> None:
    columns = {col["name"] for col in inspect(db.bind).get_columns("users")}
    if "nickname" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN nickname VARCHAR(128)"))
        db.commit()
    if "email" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN email VARCHAR(256)"))
        db.commit()
        db.execute(text("CREATE INDEX IF NOT EXISTS ix_users_email ON users (email)"))
        db.commit()
    if "avatar_url" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN avatar_url VARCHAR(512)"))
        db.commit()
    if "is_active" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN is_active BOOLEAN DEFAULT TRUE"))
        db.commit()
    if "is_proxy" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN is_proxy BOOLEAN DEFAULT FALSE"))
        db.commit()
    if "invite_code" in columns:
        pass
    else:
        db.execute(text("ALTER TABLE users ADD COLUMN invite_code VARCHAR(32)"))
        db.commit()
        db.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_invite_code ON users (invite_code)"))
        db.commit()
    if "activation_code" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN activation_code VARCHAR(10)"))
        db.commit()
        db.execute(text("CREATE INDEX IF NOT EXISTS ix_users_activation_code ON users (activation_code)"))
        db.commit()
    if "activation_expires_at" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN activation_expires_at TIMESTAMP"))
        db.commit()
    if "is_premium" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN is_premium BOOLEAN DEFAULT FALSE"))
        db.commit()
        db.execute(text("UPDATE users SET is_premium = FALSE WHERE is_premium IS NULL"))
        db.commit()
    if "premium_expires_at" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN premium_expires_at TIMESTAMP WITH TIME ZONE"))
        db.commit()


def user_has_active_pro(user: User | None) -> bool:
    if user is None or not bool(getattr(user, "is_premium", False)):
        return False
    expires_at = getattr(user, "premium_expires_at", None)
    if expires_at is None:
        return False
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)
    return expires_at > datetime.now(timezone.utc)


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


def _ensure_firebase_ready(fallback_project_id: str | None = None) -> bool:
    try:
        if firebase_admin._apps:
            return True
        project_id = (
            settings.firebase_project_id
            or os.getenv("GOOGLE_CLOUD_PROJECT")
            or fallback_project_id
        )
        if settings.firebase_credentials_path:
            cred = credentials.Certificate(settings.firebase_credentials_path)
            firebase_admin.initialize_app(cred)
        elif project_id:
            firebase_admin.initialize_app(options={"projectId": project_id})
        else:
            return False
        return True
    except Exception:
        return False


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
    firebase_ready = _ensure_firebase_ready(fallback_project_id=token_project_id)
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

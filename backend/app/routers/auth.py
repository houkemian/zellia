import logging
import secrets
import string
import json
import base64
from datetime import datetime, timedelta, timezone
from typing import Annotated

import firebase_admin
from firebase_admin import auth as firebase_auth
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import inspect, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.dependencies import get_current_user, resolve_profile_pro_display
from app.routers.pro_share import try_auto_grant_pro_share_if_eligible
from app.firebase_app import ensure_firebase_app_ready
from app.models import FamilyLink, User
from app.schemas.auth import (
    ActivateElderRequest,
    ActivateElderResponse,
    FirebaseLoginRequest,
    ProxyRegisterRequest,
    ProxyRegisterResponse,
    Token,
    UserCreate,
    UserProfileRead,
    UserProfileUpdate,
    UserRead,
    UsernameTokenRequest,
    ValidateActivationCodeRequest,
    ValidateActivationCodeResponse,
)
from app.security import create_access_token, hash_password, verify_password

logger = logging.getLogger(__name__)
router = APIRouter(tags=["auth"])
DEBUG_USERNAME = "a"
DEBUG_PASSWORD = "a"


def _ensure_firebase_auth_record_for_elder(user: User) -> None:
    """Create Firebase Auth user if missing so the account appears in Firebase Console."""
    try:
        firebase_auth.get_user(user.username)
        return
    except firebase_auth.UserNotFoundError:
        pass
    display = (user.nickname or "").strip() or user.username
    try:
        firebase_auth.create_user(
            uid=user.username,
            display_name=display[:128],
            disabled=False,
        )
    except Exception as exc:
        if "AlreadyExists" in type(exc).__name__ or "already exists" in str(exc).lower():
            return
        raise


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


def _generate_activation_code() -> str:
    alphabet = string.ascii_uppercase + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(6))


def _create_unique_activation_code(db: Session) -> str:
    for _ in range(20):
        code = _generate_activation_code()
        existing = db.execute(select(User).where(User.activation_code == code)).scalar_one_or_none()
        if existing is None:
            return code
    raise HTTPException(status_code=500, detail="Failed to generate activation code")


def _create_unique_proxy_username(db: Session) -> str:
    for _ in range(50):
        suffix = "".join(secrets.choice(string.digits) for _ in range(secrets.choice([4, 5, 6])))
        username = f"zellia_{suffix}"
        exists = db.execute(select(User.id).where(User.username == username)).first()
        if exists is None:
            return username
    raise HTTPException(status_code=500, detail="Failed to generate system username")


def _create_unique_oauth_username(db: Session, provider: str) -> str:
    if provider == "google":
        prefix = "g"
    elif provider == "microsoft":
        prefix = "m"
    else:
        prefix = "e"
    for _ in range(50):
        suffix = "".join(secrets.choice(string.digits) for _ in range(8))
        username = f"{prefix}_{suffix}"
        exists = db.execute(select(User.id).where(User.username == username)).first()
        if exists is None:
            return username
    raise HTTPException(status_code=500, detail="Failed to generate oauth username")


def _to_profile_read(db: Session, user: User) -> UserProfileRead:
    effective, display_expires, share_only = resolve_profile_pro_display(db, user)
    fallback_nickname = (user.username or "").split("@")[0] or user.username
    fallback_email = user.username
    return UserProfileRead(
        id=user.id,
        username=user.username,
        nickname=(user.nickname or "").strip() or fallback_nickname,
        email=(user.email or "").strip() or fallback_email,
        avatar_url=user.avatar_url,
        is_premium=effective,
        premium_expires_at=display_expires,
        pro_is_family_share=share_only,
    )


@router.post("/auth/register", response_model=UserRead, status_code=status.HTTP_201_CREATED)
@router.post("/register", response_model=UserRead, status_code=status.HTTP_201_CREATED, include_in_schema=False)
def register(payload: UserCreate, db: Annotated[Session, Depends(get_db)]):
    _ensure_user_profile_columns(db)
    exists = db.execute(select(User).where(User.username == payload.username)).scalar_one_or_none()
    if exists:
        raise HTTPException(status_code=400, detail="Username already registered")
    guessed_nickname = payload.username.split("@")[0] if "@" in payload.username else payload.username
    user = User(
        username=payload.username,
        hashed_password=hash_password(payload.password),
        email=payload.username,
        nickname=guessed_nickname,
        is_active=True,
        is_proxy=False,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.post("/auth/login", response_model=Token)
@router.post("/login", response_model=Token, include_in_schema=False)
def login(
    db: Annotated[Session, Depends(get_db)],
    form_data: Annotated[OAuth2PasswordRequestForm, Depends()],
):
    _ensure_user_profile_columns(db)
    user = db.execute(select(User).where(User.username == form_data.username)).scalar_one_or_none()
    # Debug convenience: auto-seed a/a test account when first used.
    if user is None and form_data.username == DEBUG_USERNAME and form_data.password == DEBUG_PASSWORD:
        user = User(
            username=DEBUG_USERNAME,
            hashed_password=hash_password(DEBUG_PASSWORD),
            nickname=DEBUG_USERNAME,
            email=DEBUG_USERNAME,
        )
        db.add(user)
        try:
            db.commit()
            db.refresh(user)
        except IntegrityError:
            db.rollback()
            user = db.execute(select(User).where(User.username == DEBUG_USERNAME)).scalar_one_or_none()

    if user is None or not verify_password(form_data.password, user.hashed_password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Incorrect username or password")
    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Account is not activated yet")
    token = create_access_token(sub=user.username)
    return Token(access_token=token)


@router.post("/auth/firebase-login", response_model=Token)
def firebase_login(
    payload: FirebaseLoginRequest,
    db: Annotated[Session, Depends(get_db)],
):
    _ensure_user_profile_columns(db)
    provider = payload.provider.strip().lower()
    if provider not in {"google", "microsoft", "password"}:
        raise HTTPException(status_code=400, detail="Unsupported provider")
    token_project_id = _extract_project_id_from_id_token(payload.id_token)
    firebase_ready = ensure_firebase_app_ready(fallback_project_id=token_project_id)
    if not firebase_ready and not token_project_id:
        raise HTTPException(status_code=503, detail="Firebase auth is not configured")

    try:
        if firebase_ready:
            claims = firebase_auth.verify_id_token(payload.id_token)
        else:
            claims = _verify_firebase_token_with_google(payload.id_token, token_project_id)
    except Exception as exc:
        # Some deployments initialize Firebase without service-account credentials.
        # In that case, fallback to Google public-key verification if project id is known.
        if token_project_id:
            try:
                claims = _verify_firebase_token_with_google(payload.id_token, token_project_id)
            except Exception as fallback_exc:
                raise HTTPException(status_code=401, detail=f"Invalid Firebase token: {fallback_exc}") from fallback_exc
        else:
            raise HTTPException(status_code=401, detail=f"Invalid Firebase token: {exc}") from exc

    firebase_provider = claims.get("firebase", {}).get("sign_in_provider")
    expected = {
        "google": "google.com",
        "microsoft": "microsoft.com",
        "password": "password",
    }[provider]
    if firebase_provider != expected:
        raise HTTPException(
            status_code=400,
            detail=f"Provider mismatch. expected={expected}, got={firebase_provider}",
        )

    email = (claims.get("email") or "").strip().lower()
    display_name = (claims.get("name") or "").strip()
    firebase_uid = (claims.get("user_id") or claims.get("uid") or "").strip()

    user = None
    if email:
        user = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    if user is None and firebase_uid:
        user = db.execute(select(User).where(User.username == firebase_uid)).scalar_one_or_none()

    if user is None:
        nickname = display_name or (email.split("@")[0] if email else f"{provider}_user")
        user = User(
            username=firebase_uid if firebase_uid and len(firebase_uid) <= 20 else _create_unique_oauth_username(db, provider),
            hashed_password=hash_password(secrets.token_urlsafe(32)),
            email=email or None,
            nickname=nickname[:128],
            is_active=True,
            is_proxy=False,
        )
        db.add(user)
        try:
            db.commit()
            db.refresh(user)
        except IntegrityError:
            db.rollback()
            if email:
                user = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
            if user is None:
                raise HTTPException(status_code=500, detail="Failed to create oauth user")

    if not user.is_active:
        user.is_active = True
        db.commit()

    token = create_access_token(sub=user.username)
    return Token(access_token=token)


@router.get("/auth/me", response_model=UserProfileRead)
def get_me(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_user_profile_columns(db)
    return _to_profile_read(db, current_user)


@router.put("/auth/me", response_model=UserProfileRead)
def update_me(
    payload: UserProfileUpdate,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_user_profile_columns(db)
    if payload.nickname is not None:
        current_user.nickname = payload.nickname.strip() or current_user.nickname
    if payload.email is not None:
        current_user.email = payload.email.strip() or current_user.email
    if payload.avatar_url is not None:
        current_user.avatar_url = payload.avatar_url.strip() or None
    db.commit()
    db.refresh(current_user)
    return _to_profile_read(db, current_user)


@router.post("/auth/proxy-register", response_model=ProxyRegisterResponse, status_code=status.HTTP_201_CREATED)
def proxy_register(
    payload: ProxyRegisterRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_user_profile_columns(db)
    nickname = payload.nickname.strip()
    if not nickname:
        raise HTTPException(status_code=400, detail="Nickname is required")
    elder_alias = (payload.elder_alias or "").strip() or nickname
    username = _create_unique_proxy_username(db)
    activation_code = _create_unique_activation_code(db)
    elder = User(
        username=username,
        email=None,
        nickname=nickname,
        hashed_password=hash_password(secrets.token_urlsafe(24)),
        is_active=False,
        is_proxy=True,
        activation_code=activation_code,
        activation_expires_at=datetime.now(timezone.utc) + timedelta(hours=72),
    )
    db.add(elder)
    db.flush()

    family_link = FamilyLink(
        caregiver_id=current_user.id,
        elder_id=elder.id,
        elder_alias=elder_alias,
        status="PENDING",
    )
    db.add(family_link)
    try_auto_grant_pro_share_if_eligible(db, current_user, elder)
    db.commit()

    return ProxyRegisterResponse(
        elder_user_id=elder.id,
        username=elder.username,
        activation_code=activation_code,
    )


@router.post("/auth/activate/validate", response_model=ValidateActivationCodeResponse)
def validate_activation_code(
    payload: ValidateActivationCodeRequest,
    db: Annotated[Session, Depends(get_db)],
):
    """Check activation code exists and is not expired (server-side; replaces client-only length checks)."""
    _ensure_user_profile_columns(db)
    now = datetime.now(timezone.utc)
    code = payload.activation_code.strip().upper()
    user = db.execute(
        select(User).where(
            User.activation_code == code,
            User.activation_expires_at.is_not(None),
            User.activation_expires_at >= now,
        )
    ).scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=400, detail="Invalid or expired activation code")
    return ValidateActivationCodeResponse(valid=True)


@router.post("/auth/activate", response_model=ActivateElderResponse)
def activate_elder_account(
    payload: ActivateElderRequest,
    db: Annotated[Session, Depends(get_db)],
):
    _ensure_user_profile_columns(db)
    now = datetime.now(timezone.utc)
    code = payload.activation_code.strip().upper()
    user = db.execute(
        select(User).where(
            User.activation_code == code,
            User.activation_expires_at.is_not(None),
            User.activation_expires_at >= now,
        )
    ).scalar_one_or_none()
    if user is None:
        raise HTTPException(status_code=400, detail="Invalid or expired activation code")

    user.hashed_password = hash_password(payload.new_password)
    user.is_active = True
    user.activation_code = None
    user.activation_expires_at = None

    links = db.execute(select(FamilyLink).where(FamilyLink.elder_id == user.id)).scalars().all()
    caregiver_ids = {link.caregiver_id for link in links}
    for link in links:
        link.status = "APPROVED"
        # Match /family/requests/.../decision: approved caregivers must be MANAGE so
        # vitals/medications manage endpoints (e.g. POST /medications/plan) authorize.
        link.permissions = "MANAGE"
    for caregiver_id in caregiver_ids:
        caregiver = db.get(User, caregiver_id)
        if caregiver is not None:
            try_auto_grant_pro_share_if_eligible(db, caregiver, user)

    db.commit()
    db.refresh(user)

    custom_token_str: str | None = None
    if ensure_firebase_app_ready():
        try:
            _ensure_firebase_auth_record_for_elder(user)
        except Exception as exc:
            logger.warning(
                "Could not provision Firebase Auth user %s (Console may miss until sign-in): %s",
                user.username,
                exc,
            )
        try:
            custom_token = firebase_auth.create_custom_token(
                user.username,
                {"provider": "family_activation", "user_id": user.id},
            )
            if isinstance(custom_token, bytes):
                custom_token_str = custom_token.decode("utf-8")
            else:
                custom_token_str = str(custom_token)
        except Exception as exc:
            logger.warning("create_custom_token failed for %s: %s", user.username, exc)
            custom_token_str = None

    if custom_token_str:
        return ActivateElderResponse(
            username=user.username,
            firebase_custom_token=custom_token_str,
        )

    jwt_token = create_access_token(sub=user.username)
    return ActivateElderResponse(
        username=user.username,
        access_token=jwt_token,
    )


@router.post("/auth/username-token", response_model=ActivateElderResponse)
def username_token(
    payload: UsernameTokenRequest,
    db: Annotated[Session, Depends(get_db)],
):
    """Login for family-activation accounts whose username is not an email (e.g. zellia_2511).
    Returns a Firebase Custom Token when the Admin SDK is ready, otherwise a legacy JWT."""
    _ensure_user_profile_columns(db)
    user = db.execute(
        select(User).where(User.username == payload.username.strip())
    ).scalar_one_or_none()
    if user is None or not user.is_active or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="incorrect_credentials",
        )

    custom_token_str: str | None = None
    if ensure_firebase_app_ready():
        try:
            _ensure_firebase_auth_record_for_elder(user)
        except Exception as exc:
            logger.warning("Could not provision Firebase Auth user %s: %s", user.username, exc)
        try:
            custom_token = firebase_auth.create_custom_token(
                user.username,
                {"provider": "username_password", "user_id": user.id},
            )
            if isinstance(custom_token, bytes):
                custom_token_str = custom_token.decode("utf-8")
            else:
                custom_token_str = str(custom_token)
        except Exception as exc:
            logger.warning("create_custom_token failed for %s: %s", user.username, exc)
            custom_token_str = None

    if custom_token_str:
        return ActivateElderResponse(
            username=user.username,
            firebase_custom_token=custom_token_str,
        )

    jwt_token = create_access_token(sub=user.username)
    return ActivateElderResponse(
        username=user.username,
        access_token=jwt_token,
    )

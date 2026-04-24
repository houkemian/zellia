from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import inspect, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models import User
from app.schemas.auth import Token, UserCreate, UserProfileRead, UserProfileUpdate, UserRead
from app.security import create_access_token, hash_password, verify_password

router = APIRouter(tags=["auth"])
DEBUG_USERNAME = "a"
DEBUG_PASSWORD = "a"


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


def _to_profile_read(user: User) -> UserProfileRead:
    fallback_nickname = (user.username or "").split("@")[0] or user.username
    fallback_email = user.username
    return UserProfileRead(
        id=user.id,
        username=user.username,
        nickname=(user.nickname or "").strip() or fallback_nickname,
        email=(user.email or "").strip() or fallback_email,
        avatar_url=user.avatar_url,
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
    token = create_access_token(sub=user.username)
    return Token(access_token=token)


@router.get("/auth/me", response_model=UserProfileRead)
def get_me(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    _ensure_user_profile_columns(db)
    return _to_profile_read(current_user)


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
    return _to_profile_read(current_user)

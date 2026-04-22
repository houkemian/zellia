from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.exc import IntegrityError
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User
from app.schemas.auth import Token, UserCreate, UserRead
from app.security import create_access_token, hash_password, verify_password

router = APIRouter(tags=["auth"])
DEBUG_USERNAME = "a"
DEBUG_PASSWORD = "a"


@router.post("/auth/register", response_model=UserRead, status_code=status.HTTP_201_CREATED)
@router.post("/register", response_model=UserRead, status_code=status.HTTP_201_CREATED, include_in_schema=False)
def register(payload: UserCreate, db: Annotated[Session, Depends(get_db)]):
    exists = db.execute(select(User).where(User.username == payload.username)).scalar_one_or_none()
    if exists:
        raise HTTPException(status_code=400, detail="Username already registered")
    user = User(username=payload.username, hashed_password=hash_password(payload.password))
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
    user = db.execute(select(User).where(User.username == form_data.username)).scalar_one_or_none()
    # Debug convenience: auto-seed a/a test account when first used.
    if user is None and form_data.username == DEBUG_USERNAME and form_data.password == DEBUG_PASSWORD:
        user = User(username=DEBUG_USERNAME, hashed_password=hash_password(DEBUG_PASSWORD))
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

from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import inspect, text
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User
from app.security import decode_token

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")


def _ensure_user_invite_code_column(db: Session) -> None:
    columns = {col["name"] for col in inspect(db.bind).get_columns("users")}
    if "invite_code" in columns:
        return
    db.execute(text("ALTER TABLE users ADD COLUMN invite_code VARCHAR(32)"))
    db.commit()
    db.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_invite_code ON users (invite_code)"))
    db.commit()


def get_current_user(
    token: Annotated[str, Depends(oauth2_scheme)],
    db: Annotated[Session, Depends(get_db)],
) -> User:
    _ensure_user_invite_code_column(db)
    username = decode_token(token)
    if username is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    user = db.query(User).filter(User.username == username).first()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user

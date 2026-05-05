from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy import inspect, text
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User
from app.security import decode_token

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


def get_current_user(
    token: Annotated[str, Depends(oauth2_scheme)],
    db: Annotated[Session, Depends(get_db)],
) -> User:
    _ensure_user_profile_columns(db)
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


def require_pro_user(
    current_user: Annotated[User, Depends(get_current_user)],
) -> User:
    if not current_user.is_premium:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="此功能仅限 PRO 用户使用",
        )
    return current_user

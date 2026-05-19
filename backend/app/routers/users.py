"""Account lifecycle endpoints."""

from __future__ import annotations

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models import User
from app.services.account_deletion_service import delete_user_account

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/users", tags=["users"])


@router.delete("/delete", status_code=status.HTTP_204_NO_CONTENT)
def delete_current_user_account(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
):
    """Permanently delete the authenticated user's account and personal data."""
    user = db.get(User, current_user.id)
    if user is None:
        return None
    delete_user_account(db, user)
    return None

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user
from app.models import FamilyLink, User
from app.schemas.snapshot import ClinicalSnapshotRead
from app.services.clinical_snapshot_service import build_clinical_snapshot

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/snapshots", tags=["snapshots"])


def _resolve_target_user_id(db: Session, current_user: User, target_user_id: int | None) -> int:
    if target_user_id is None or target_user_id == current_user.id:
        return current_user.id
    try:
        approved = db.execute(
            select(FamilyLink.id).where(
                FamilyLink.caregiver_id == current_user.id,
                FamilyLink.elder_id == target_user_id,
                FamilyLink.status == "APPROVED",
            )
        ).first()
    except Exception as exc:
        logger.exception("snapshots: family permission check failed: %s", exc)
        raise HTTPException(status_code=500, detail="Permission check failed") from exc
    if approved is None:
        raise HTTPException(status_code=403, detail="No permission to view target user")
    return target_user_id


@router.get("/clinical", response_model=ClinicalSnapshotRead)
def clinical_snapshot(
    db: Annotated[Session, Depends(get_db)],
    current_user: Annotated[User, Depends(get_current_user)],
    target_user_id: Annotated[int | None, Query()] = None,
):
    """Single round-trip snapshot: latest BP/BS + today's medication slots (for home widgets)."""
    user_id = _resolve_target_user_id(db, current_user, target_user_id)
    try:
        return build_clinical_snapshot(db, user_id)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("clinical_snapshot endpoint failed: %s", exc)
        raise HTTPException(status_code=500, detail="Failed to load clinical snapshot") from exc

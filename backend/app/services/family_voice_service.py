"""Family voice URLs stored per approved caregiver ↔ elder link."""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import FamilyLink, User
from app.services.r2_service import resolve_voice_download_url


def get_approved_link(
    db: Session, *, caregiver_id: int, elder_id: int
) -> FamilyLink | None:
    return db.execute(
        select(FamilyLink).where(
            FamilyLink.caregiver_id == caregiver_id,
            FamilyLink.elder_id == elder_id,
            FamilyLink.status == "APPROVED",
        )
    ).scalar_one_or_none()


def stored_voice_url_for_pair(
    db: Session, *, caregiver_id: int, elder_id: int
) -> str | None:
    link = get_approved_link(db, caregiver_id=caregiver_id, elder_id=elder_id)
    if link is not None:
        raw = getattr(link, "family_voice_url", None)
        if raw and str(raw).strip():
            return str(raw).strip()
    elder = db.get(User, elder_id)
    legacy = (getattr(elder, "family_voice_url", None) or "").strip() if elder else ""
    return legacy or None


def resolve_latest_elder_voice(
    db: Session, elder_id: int
) -> tuple[str | None, int | None]:
    """Presigned download URL and caregiver_id for the newest link voice."""
    rows = db.execute(
        select(FamilyLink)
        .where(
            FamilyLink.elder_id == elder_id,
            FamilyLink.status == "APPROVED",
            FamilyLink.family_voice_url.isnot(None),
        )
        .order_by(FamilyLink.family_voice_updated_at.desc().nullslast())
    ).scalars().all()
    for link in rows:
        stored = (link.family_voice_url or "").strip()
        if not stored:
            continue
        download = resolve_voice_download_url(
            user_id=elder_id, stored_url=stored
        )
        if download:
            return download, link.caregiver_id

    elder = db.get(User, elder_id)
    legacy = (getattr(elder, "family_voice_url", None) or "").strip() if elder else ""
    if legacy:
        download = resolve_voice_download_url(user_id=elder_id, stored_url=legacy)
        if download:
            legacy_link = db.execute(
                select(FamilyLink)
                .where(
                    FamilyLink.elder_id == elder_id,
                    FamilyLink.status == "APPROVED",
                )
                .order_by(FamilyLink.id.desc())
            ).scalars().first()
            caregiver_id = legacy_link.caregiver_id if legacy_link else None
            return download, caregiver_id
    return None, None


def resolve_voice_for_pair(
    db: Session, *, caregiver_id: int, elder_id: int
) -> str | None:
    stored = stored_voice_url_for_pair(
        db, caregiver_id=caregiver_id, elder_id=elder_id
    )
    if not stored:
        return None
    return resolve_voice_download_url(user_id=elder_id, stored_url=stored)


def apply_voice_to_link(link: FamilyLink, voice_url: str) -> None:
    url = voice_url.strip()
    link.family_voice_url = url
    link.family_voice_updated_at = datetime.now(timezone.utc)

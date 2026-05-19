"""Permanently delete a user account and associated personal data."""

from __future__ import annotations

import logging

from sqlalchemy import delete, or_, select
from sqlalchemy.orm import Session

from app.models import (
    BloodPressureRecord,
    BloodSugarRecord,
    DeviceToken,
    FamilyLink,
    FamilyLinkActionLog,
    MedicationLog,
    MedicationPlan,
    MedicationPokeEvent,
    ProShare,
    SubscriptionEvent,
    User,
)
from app.services.r2_service import delete_stored_voice_url, object_key_from_stored_public_url

logger = logging.getLogger(__name__)


def _collect_voice_urls(db: Session, user: User) -> list[str]:
    urls: list[str] = []
    if user.family_voice_url and user.family_voice_url.strip():
        urls.append(user.family_voice_url.strip())

    plans = db.execute(
        select(MedicationPlan.voice_url).where(
            MedicationPlan.user_id == user.id,
            MedicationPlan.voice_url.isnot(None),
        )
    ).scalars().all()
    for raw in plans:
        if raw and str(raw).strip():
            urls.append(str(raw).strip())

    link_voices = db.execute(
        select(FamilyLink.family_voice_url).where(
            or_(FamilyLink.elder_id == user.id, FamilyLink.caregiver_id == user.id),
            FamilyLink.family_voice_url.isnot(None),
        )
    ).scalars().all()
    for raw in link_voices:
        if raw and str(raw).strip():
            urls.append(str(raw).strip())

    return urls


def _purge_r2_voice_objects(urls: list[str]) -> None:
    seen: set[str] = set()
    for url in urls:
        key = object_key_from_stored_public_url(url)
        if not key or key in seen:
            continue
        seen.add(key)
        try:
            delete_stored_voice_url(url)
        except Exception as exc:
            logger.warning("account delete: R2 purge failed key=%s: %s", key, exc)


def delete_user_account(db: Session, user: User) -> None:
    """Delete all rows owned by [user] and remove the user row."""
    user_id = user.id
    voice_urls = _collect_voice_urls(db, user)

    plan_ids = list(
        db.execute(
            select(MedicationPlan.id).where(MedicationPlan.user_id == user_id)
        ).scalars().all()
    )
    if plan_ids:
        db.execute(
            delete(MedicationPokeEvent).where(
                MedicationPokeEvent.plan_id.in_(plan_ids)
            )
        )
        db.execute(
            delete(MedicationLog).where(MedicationLog.plan_id.in_(plan_ids))
        )
        db.execute(delete(MedicationPlan).where(MedicationPlan.user_id == user_id))

    db.execute(delete(MedicationLog).where(MedicationLog.user_id == user_id))
    db.execute(
        delete(MedicationPokeEvent).where(MedicationPokeEvent.caregiver_id == user_id)
    )
    db.execute(
        delete(BloodPressureRecord).where(BloodPressureRecord.user_id == user_id)
    )
    db.execute(delete(BloodSugarRecord).where(BloodSugarRecord.user_id == user_id))
    db.execute(delete(DeviceToken).where(DeviceToken.user_id == user_id))
    db.execute(delete(ProShare).where(ProShare.owner_id == user_id))
    db.execute(delete(ProShare).where(ProShare.target_user_id == user_id))
    db.execute(
        delete(FamilyLinkActionLog).where(
            or_(
                FamilyLinkActionLog.actor_user_id == user_id,
                FamilyLinkActionLog.elder_id == user_id,
                FamilyLinkActionLog.caregiver_id == user_id,
            )
        )
    )
    db.execute(
        delete(FamilyLink).where(
            or_(FamilyLink.elder_id == user_id, FamilyLink.caregiver_id == user_id)
        )
    )
    db.execute(
        delete(SubscriptionEvent).where(SubscriptionEvent.user_id == user_id)
    )

    db.delete(user)
    db.commit()

    _purge_r2_voice_objects(voice_urls)

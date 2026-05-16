"""Reusable SQLAlchemy loader options — prevent lazy-load explosions and join cartesian products."""

from sqlalchemy.orm import joinedload, load_only, noload

from app.models import FamilyLink, ProShare, User

# Columns needed by family / pro-share DTO builders only (never load hashed_password).
USER_SUMMARY_COLUMNS = load_only(
    User.id,
    User.username,
    User.nickname,
    User.email,
    User.avatar_url,
    User.is_proxy,
    User.is_premium,
    User.premium_expires_at,
)

USER_SUMMARY_NO_BACKREF = (
    USER_SUMMARY_COLUMNS,
    noload(User.medication_plans),
    noload(User.medication_logs),
    noload(User.blood_pressure_records),
    noload(User.blood_sugar_records),
    noload(User.elder_links),
    noload(User.caregiver_links),
    noload(User.device_tokens),
    noload(User.subscription_events),
    noload(User.pro_shares_owned),
    noload(User.pro_share_as_target),
)


def family_link_with_users():
    """Eager-load elder + caregiver without pulling User back-references (no A↔B nesting)."""
    return (
        joinedload(FamilyLink.elder).options(*USER_SUMMARY_NO_BACKREF),
        joinedload(FamilyLink.caregiver).options(*USER_SUMMARY_NO_BACKREF),
    )


def pro_share_with_target_user():
    return joinedload(ProShare.target_user).options(*USER_SUMMARY_NO_BACKREF)


def pro_share_with_owner():
    return joinedload(ProShare.owner).options(*USER_SUMMARY_NO_BACKREF)

"""ORM → 扁平 Pydantic DTO；禁止将 SQLAlchemy 模型直接作为 response 返回。"""

from app.models import FamilyLink, ProShare
from app.schemas.family import ApprovedFamilyMemberResponse, FamilyLinkResponse
from app.schemas.pro_share import ProShareItemResponse
from app.schemas.user import user_to_minimal


def family_link_to_response(link: FamilyLink) -> FamilyLinkResponse:
    elder = user_to_minimal(link.elder)
    caregiver = user_to_minimal(link.caregiver)
    caregiver_email = getattr(link.caregiver, "email", None)
    return FamilyLinkResponse(
        id=link.id,
        link_id=link.id,
        elder_id=link.elder_id,
        caregiver_id=link.caregiver_id,
        status=link.status,
        permissions=link.permissions,
        elder_alias=link.elder_alias,
        caregiver_alias=link.caregiver_alias,
        receive_weekly_report=bool(link.receive_weekly_report),
        elder=elder,
        caregiver=caregiver,
        elder_username=elder.username,
        caregiver_username=caregiver.username,
        caregiver_nickname=caregiver.nickname,
        caregiver_email=(caregiver_email or "").strip() or None if caregiver_email else None,
        elder_avatar_url=elder.avatar_url,
        caregiver_avatar_url=caregiver.avatar_url,
    )


def approved_member_to_response(
    link: FamilyLink,
    *,
    elder_has_active_pro: bool,
    elder_pro_share_locked_other: bool,
) -> ApprovedFamilyMemberResponse:
    elder = user_to_minimal(link.elder, is_premium=elder_has_active_pro)
    caregiver = user_to_minimal(link.caregiver)
    return ApprovedFamilyMemberResponse(
        link_id=link.id,
        elder_id=link.elder_id,
        caregiver_id=link.caregiver_id,
        elder_alias=link.elder_alias,
        caregiver_alias=link.caregiver_alias,
        receive_weekly_report=bool(link.receive_weekly_report),
        elder_pro_share_locked_other=elder_pro_share_locked_other,
        elder=elder,
        caregiver=caregiver,
        elder_username=elder.username,
        caregiver_username=caregiver.username,
        caregiver_nickname=caregiver.nickname,
        elder_avatar_url=elder.avatar_url,
        caregiver_avatar_url=caregiver.avatar_url,
        elder_is_proxy=elder.is_proxy,
        elder_has_active_pro=elder_has_active_pro,
    )


def pro_share_to_item(row: ProShare) -> ProShareItemResponse:
    target = user_to_minimal(row.target_user)
    return ProShareItemResponse(
        share_id=row.id,
        target_user=target,
        user_id=target.id,
        nickname=target.nickname,
        avatar_url=target.avatar_url,
        is_proxy=target.is_proxy,
    )

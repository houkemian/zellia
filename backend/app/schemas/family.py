"""家庭关系扁平 DTO：用户字段仅用 UserMinimal，禁止套娃完整 User。"""

from pydantic import BaseModel, ConfigDict

from app.schemas.user import UserMinimal


class InviteCodeResponse(BaseModel):
    invite_code: str


class LinkApplyRequest(BaseModel):
    invite_code: str
    elder_alias: str | None = None


class LinkDecisionRequest(BaseModel):
    approved: bool
    caregiver_alias: str | None = None


class WeeklyReportToggleRequest(BaseModel):
    receive_weekly_report: bool


class ResetElderPasswordRequest(BaseModel):
    elder_id: int
    temp_password: str


class QrTokenResponse(BaseModel):
    qr_payload: str
    expires_in: int


class ScanQrRequest(BaseModel):
    token: str
    family_alias: str | None = None


class ScanQrResponse(BaseModel):
    success: bool
    link_id: int
    status: str
    elder_id: int
    elder_username: str
    elder_nickname: str | None


class FamilyLinkResponse(BaseModel):
    """家庭绑定关系；elder/caregiver 仅 UserMinimal。"""

    model_config = ConfigDict(from_attributes=True, extra="ignore")

    id: int
    link_id: int
    elder_id: int
    caregiver_id: int
    status: str
    permissions: str
    elder_alias: str | None = None
    caregiver_alias: str | None = None
    receive_weekly_report: bool = True
    # 使用扁平模型防止循环引用
    elder: UserMinimal
    caregiver: UserMinimal
    # 兼容既有移动端字段（由 mapper 与 elder/caregiver 同步填充）
    elder_username: str
    caregiver_username: str
    caregiver_nickname: str | None = None
    caregiver_email: str | None = None
    elder_avatar_url: str | None = None
    caregiver_avatar_url: str | None = None


class ApprovedFamilyMemberResponse(BaseModel):
    """已批准家庭成员；elder/caregiver 仅 UserMinimal。"""

    model_config = ConfigDict(from_attributes=True, extra="ignore")

    link_id: int
    elder_id: int
    caregiver_id: int
    elder_alias: str | None = None
    caregiver_alias: str | None = None
    receive_weekly_report: bool = True
    elder_pro_share_locked_other: bool = False
    # 使用扁平模型防止循环引用
    elder: UserMinimal
    caregiver: UserMinimal
    # 兼容既有移动端字段
    elder_username: str
    caregiver_username: str
    caregiver_nickname: str | None = None
    elder_avatar_url: str | None = None
    caregiver_avatar_url: str | None = None
    elder_is_proxy: bool = False
    elder_has_active_pro: bool = False


# 路由层历史别名
FamilyLinkRead = FamilyLinkResponse
ApprovedFamilyLinkRead = ApprovedFamilyMemberResponse
InviteCodeRead = InviteCodeResponse
LinkApplyPayload = LinkApplyRequest
LinkDecisionPayload = LinkDecisionRequest
WeeklyReportTogglePayload = WeeklyReportToggleRequest
ResetElderPasswordPayload = ResetElderPasswordRequest
QrTokenRead = QrTokenResponse
ScanQrPayload = ScanQrRequest
ScanQrResult = ScanQrResponse

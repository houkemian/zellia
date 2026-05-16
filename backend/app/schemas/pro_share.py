"""PRO 共享扁平 DTO：target_user / owner 仅 UserMinimal。"""

from pydantic import BaseModel, ConfigDict

from app.schemas.user import UserMinimal


class ProShareAddRequest(BaseModel):
    target_user_id: int


class ProShareItemResponse(BaseModel):
    """单条共享记录；target_user 仅 UserMinimal。"""

    model_config = ConfigDict(from_attributes=True, extra="ignore")

    share_id: int
    # 使用扁平模型防止循环引用
    target_user: UserMinimal
    # 兼容既有移动端字段
    user_id: int
    nickname: str | None = None
    avatar_url: str | None = None
    is_proxy: bool = False


class ProShareMyResponse(BaseModel):
    model_config = ConfigDict(extra="ignore")

    max_shares: int
    used_shares: int
    shared_users: list[ProShareItemResponse]


# 路由层历史别名
ProShareAddPayload = ProShareAddRequest
ProShareSharedUserRead = ProShareItemResponse
ProShareMyRead = ProShareMyResponse

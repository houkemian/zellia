"""扁平用户 DTO：仅标量字段，禁止嵌套 caregivers / elders / vitals 等关系列表。"""

from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.models import User


class UserMinimal(BaseModel):
    """关系响应中唯一允许嵌套的用户类型；使用扁平模型防止循环引用。"""

    model_config = ConfigDict(from_attributes=True, extra="ignore")

    id: int
    username: str
    nickname: str | None = None
    avatar_url: str | None = None
    is_premium: bool = False
    is_proxy: bool = False


class UserPublicProfile(BaseModel):
    """当前用户资料（/auth/me）；不含 hashed_password 与任何 relationship。"""

    model_config = ConfigDict(from_attributes=True, extra="ignore")

    id: int
    username: str
    nickname: str
    email: str
    avatar_url: str | None = None
    is_premium: bool = False
    premium_expires_at: datetime | None = None
    pro_is_family_share: bool = False


# 兼容旧名
UserBasicInfo = UserMinimal


def user_to_minimal(user: User, *, is_premium: bool | None = None) -> UserMinimal:
    """从 ORM User 提取标量字段，不触发 relationship 遍历。"""
    premium = bool(is_premium) if is_premium is not None else False
    return UserMinimal(
        id=user.id,
        username=user.username,
        nickname=(user.nickname or "").strip() or None,
        avatar_url=user.avatar_url,
        is_premium=premium,
        is_proxy=bool(user.is_proxy),
    )

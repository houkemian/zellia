from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.user import UserPublicProfile

# 资料接口与 UserPublicProfile 相同（扁平、无 relationship）
UserProfileRead = UserPublicProfile


class UserCreate(BaseModel):
    username: str = Field(min_length=1, max_length=128)
    password: str = Field(min_length=1, max_length=256)


class UserRead(BaseModel):
    id: int
    username: str

    model_config = ConfigDict(from_attributes=True, extra="ignore")


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserProfileUpdate(BaseModel):
    nickname: str | None = Field(default=None, min_length=1, max_length=128)
    email: str | None = Field(default=None, min_length=3, max_length=256)
    avatar_url: str | None = Field(default=None, min_length=1, max_length=512)


class ProxyRegisterRequest(BaseModel):
    nickname: str = Field(min_length=1, max_length=128)
    elder_alias: str | None = Field(default=None, min_length=1, max_length=128)


class ProxyRegisterResponse(BaseModel):
    elder_user_id: int
    username: str
    activation_code: str


class ActivateElderRequest(BaseModel):
    activation_code: str = Field(min_length=6, max_length=10)
    new_password: str = Field(min_length=6, max_length=256)


class ActivateElderResponse(BaseModel):
    """Prefer firebase_custom_token (Firebase Custom Auth). If Admin SDK cannot mint a token, access_token is a JWT fallback."""

    username: str
    firebase_custom_token: str | None = None
    access_token: str | None = None


class ValidateActivationCodeRequest(BaseModel):
    activation_code: str = Field(min_length=6, max_length=10)


class ValidateActivationCodeResponse(BaseModel):
    valid: bool = True


class UsernameTokenRequest(BaseModel):
    username: str = Field(min_length=1, max_length=128)
    password: str = Field(min_length=1, max_length=256)


class FirebaseLoginRequest(BaseModel):
    provider: str = Field(min_length=1, max_length=32)
    id_token: str = Field(min_length=1, max_length=4096)
    access_token: str | None = Field(default=None, min_length=1, max_length=4096)


class UsernameTokenRequest(BaseModel):
    username: str = Field(min_length=1, max_length=128)
    password: str = Field(min_length=1, max_length=256)

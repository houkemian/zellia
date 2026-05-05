from pydantic import BaseModel, Field


class UserCreate(BaseModel):
    username: str = Field(min_length=1, max_length=128)
    password: str = Field(min_length=1, max_length=256)


class UserRead(BaseModel):
    id: int
    username: str

    model_config = {"from_attributes": True}


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserProfileRead(BaseModel):
    id: int
    username: str
    nickname: str
    email: str
    avatar_url: str | None = None
    is_premium: bool = False


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
    access_token: str
    token_type: str = "bearer"
    username: str


class FirebaseLoginRequest(BaseModel):
    provider: str = Field(min_length=1, max_length=32)
    id_token: str = Field(min_length=1, max_length=4096)
    access_token: str | None = Field(default=None, min_length=1, max_length=4096)

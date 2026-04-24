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


class UserProfileUpdate(BaseModel):
    nickname: str | None = Field(default=None, min_length=1, max_length=128)
    email: str | None = Field(default=None, min_length=3, max_length=256)
    avatar_url: str | None = Field(default=None, min_length=1, max_length=512)

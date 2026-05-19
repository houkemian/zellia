from datetime import datetime, timezone

from pydantic import BaseModel, Field, field_validator


def _ensure_tz_aware(value: datetime) -> datetime:
    if value.tzinfo is None or value.tzinfo.utcoffset(value) is None:
        raise ValueError("datetime must include timezone information")
    return value.astimezone(timezone.utc)


class BloodPressureCreate(BaseModel):
    systolic: int = Field(ge=1, le=300)
    diastolic: int = Field(ge=1, le=200)
    heart_rate: int | None = Field(default=None, ge=1, le=300)
    measured_at: datetime | None = None
    idempotency_key: str | None = Field(default=None, max_length=36)
    created_at_local: datetime | None = None

    @field_validator("measured_at", "created_at_local")
    @classmethod
    def tz_aware_optional(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        return _ensure_tz_aware(value)


class BloodPressureRead(BaseModel):
    id: int
    user_id: int
    systolic: int
    diastolic: int
    heart_rate: int | None
    measured_at: datetime
    created_at_local: datetime | None = None

    model_config = {"from_attributes": True}


class BloodSugarCreate(BaseModel):
    level: float = Field(gt=0)
    condition: str = Field(max_length=64)
    measured_at: datetime | None = None
    idempotency_key: str | None = Field(default=None, max_length=36)
    created_at_local: datetime | None = None

    @field_validator("measured_at", "created_at_local")
    @classmethod
    def tz_aware_optional(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        return _ensure_tz_aware(value)


class BloodSugarRead(BaseModel):
    id: int
    user_id: int
    level: float
    condition: str
    measured_at: datetime
    created_at_local: datetime | None = None

    model_config = {"from_attributes": True}


class BloodPressureListResponse(BaseModel):
    items: list[BloodPressureRead]
    total: int
    page: int
    page_size: int


class BloodSugarListResponse(BaseModel):
    items: list[BloodSugarRead]
    total: int
    page: int
    page_size: int

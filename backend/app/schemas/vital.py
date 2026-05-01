from datetime import datetime, timezone

from pydantic import BaseModel, Field, field_validator


class BloodPressureCreate(BaseModel):
    systolic: int = Field(ge=1, le=300)
    diastolic: int = Field(ge=1, le=200)
    heart_rate: int | None = Field(default=None, ge=1, le=300)
    measured_at: datetime

    @field_validator("measured_at")
    @classmethod
    def measured_at_must_be_timezone_aware(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.tzinfo.utcoffset(value) is None:
            raise ValueError("measured_at must include timezone information")
        return value.astimezone(timezone.utc)


class BloodPressureRead(BaseModel):
    id: int
    user_id: int
    systolic: int
    diastolic: int
    heart_rate: int | None
    measured_at: datetime

    model_config = {"from_attributes": True}


class BloodSugarCreate(BaseModel):
    level: float = Field(gt=0)
    condition: str = Field(max_length=64)
    measured_at: datetime

    @field_validator("measured_at")
    @classmethod
    def measured_at_must_be_timezone_aware(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.tzinfo.utcoffset(value) is None:
            raise ValueError("measured_at must include timezone information")
        return value.astimezone(timezone.utc)


class BloodSugarRead(BaseModel):
    id: int
    user_id: int
    level: float
    condition: str
    measured_at: datetime

    model_config = {"from_attributes": True}

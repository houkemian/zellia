from datetime import datetime

from pydantic import BaseModel, Field


class BloodPressureCreate(BaseModel):
    systolic: int = Field(ge=1, le=300)
    diastolic: int = Field(ge=1, le=200)
    heart_rate: int | None = Field(default=None, ge=1, le=300)
    measured_at: datetime


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


class BloodSugarRead(BaseModel):
    id: int
    user_id: int
    level: float
    condition: str
    measured_at: datetime

    model_config = {"from_attributes": True}

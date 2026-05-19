from datetime import date, datetime, time, timezone

from pydantic import BaseModel, Field, field_validator


class MedicationPlanCreate(BaseModel):
    name: str
    dosage: str
    start_date: date
    end_date: date
    times_a_day: str = Field(description='Comma-separated times, e.g. "08:00,12:00,18:00"')
    notify_missed: bool = True
    notify_delay_minutes: int = Field(default=60, ge=1, le=720)
    target_user_id: int | None = None


class MedicationPlanUpdate(BaseModel):
    name: str
    dosage: str
    start_date: date
    end_date: date
    times_a_day: str = Field(description='Comma-separated times, e.g. "08:00,12:00,18:00"')
    notify_missed: bool = True
    notify_delay_minutes: int = Field(default=60, ge=1, le=720)
    target_user_id: int | None = None


class MedicationPlanRead(BaseModel):
    id: int
    user_id: int
    name: str
    dosage: str
    start_date: date
    end_date: date
    times_a_day: str
    notify_missed: bool
    notify_delay_minutes: int
    voice_url: str | None = None
    is_active: bool

    model_config = {"from_attributes": True}


class VoiceUploadUrlResponse(BaseModel):
    upload_url: str
    voice_url: str = Field(description="Public R2 URL to send in PATCH after PUT succeeds")
    content_type: str = "audio/x-m4a"
    expires_in: int = 300


class VoiceDownloadUrlResponse(BaseModel):
    download_url: str
    expires_in: int = 3600


class VoiceUrlUpdate(BaseModel):
    voice_url: str = Field(min_length=8, max_length=1024)
    user_id: int | None = None


class MedicationLogCreate(BaseModel):
    taken_date: date
    taken_time: time
    is_taken: bool
    idempotency_key: str | None = Field(default=None, max_length=36)
    created_at_local: datetime | None = None

    @field_validator("created_at_local")
    @classmethod
    def created_at_local_tz_aware(cls, value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None or value.tzinfo.utcoffset(value) is None:
            raise ValueError("created_at_local must include timezone information")
        return value.astimezone(timezone.utc)


class TodayMedicationItem(BaseModel):
    plan_id: int
    name: str
    dosage: str
    scheduled_time: str
    taken_date: date
    log_id: int | None = None
    is_taken: bool | None = None
    checked_at: datetime | None = None
    notify_missed: bool = True
    notify_delay_minutes: int = 60
    voice_url: str | None = None
    family_voice_caregiver_id: int | None = None

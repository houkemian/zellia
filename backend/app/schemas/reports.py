"""Weekly summary API schemas."""

from pydantic import BaseModel, ConfigDict


class WeeklySummaryPatient(BaseModel):
    user_id: int
    username: str
    nickname: str | None = None
    display_name: str


class WeeklySummaryPeriod(BaseModel):
    start_date: str
    end_date: str


class WeeklySummaryMedication(BaseModel):
    taken_count: int
    total_tasks: int
    missed_count: int
    adherence_percent: float


class WeeklySummaryBloodPressure(BaseModel):
    average_systolic: float | None = None
    average_diastolic: float | None = None
    average_heart_rate: float | None = None
    record_count: int = 0
    abnormal_count: int = 0


class WeeklySummaryBloodSugar(BaseModel):
    average_level: float | None = None
    record_count: int = 0
    abnormal_count: int = 0


class WeeklySummaryResponse(BaseModel):
    """Frozen R2 JSON and live GET /weekly-summary share this shape."""

    model_config = ConfigDict(extra="ignore")

    days: int
    patient: WeeklySummaryPatient
    period: WeeklySummaryPeriod
    medication: WeeklySummaryMedication
    blood_pressure: WeeklySummaryBloodPressure
    blood_sugar: WeeklySummaryBloodSugar
    iso_year: int | None = None
    iso_week: int | None = None


class WeeklySummaryListItem(BaseModel):
    week_label: str
    url: str
    is_frozen: bool
    snapshot_exists: bool = False
    iso_year: int | None = None
    iso_week: int | None = None

from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.schemas.medication import TodayMedicationItem
from app.schemas.vital import BloodPressureRead, BloodSugarRead


class ClinicalSnapshotRead(BaseModel):
    """Latest vitals + today's medications for widgets and quick dashboards."""

    model_config = ConfigDict(from_attributes=True)

    user_id: int
    latest_blood_pressure: BloodPressureRead | None = None
    latest_blood_sugar: BloodSugarRead | None = None
    medications_today: list[TodayMedicationItem] = []
    generated_at: datetime

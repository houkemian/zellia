from datetime import date, datetime, time, timezone

from sqlalchemy import BigInteger, Boolean, Date, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    username: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(256))
    nickname: Mapped[str | None] = mapped_column(String(128), nullable=True)
    email: Mapped[str | None] = mapped_column(String(256), nullable=True, index=True)
    avatar_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_proxy: Mapped[bool] = mapped_column(Boolean, default=False)
    invite_code: Mapped[str | None] = mapped_column(String(32), unique=True, index=True, nullable=True)
    activation_code: Mapped[str | None] = mapped_column(String(10), nullable=True, index=True)
    activation_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    is_premium: Mapped[bool] = mapped_column(Boolean, default=False)
    premium_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    medication_plans: Mapped[list["MedicationPlan"]] = relationship(back_populates="user")
    medication_logs: Mapped[list["MedicationLog"]] = relationship(back_populates="user")
    blood_pressure_records: Mapped[list["BloodPressureRecord"]] = relationship(back_populates="user")
    blood_sugar_records: Mapped[list["BloodSugarRecord"]] = relationship(back_populates="user")
    elder_links: Mapped[list["FamilyLink"]] = relationship(
        back_populates="elder", foreign_keys="FamilyLink.elder_id"
    )
    caregiver_links: Mapped[list["FamilyLink"]] = relationship(
        back_populates="caregiver", foreign_keys="FamilyLink.caregiver_id"
    )
    device_tokens: Mapped[list["DeviceToken"]] = relationship(back_populates="user")
    subscription_events: Mapped[list["SubscriptionEvent"]] = relationship(back_populates="user")


class MedicationPlan(Base):
    __tablename__ = "medication_plans"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    name: Mapped[str] = mapped_column(String(256))
    dosage: Mapped[str] = mapped_column(String(256))
    start_date: Mapped[date] = mapped_column(Date)
    end_date: Mapped[date] = mapped_column(Date)
    times_a_day: Mapped[str] = mapped_column(Text)  # e.g. "08:00,12:00,18:00"
    notify_missed: Mapped[bool] = mapped_column(Boolean, default=True)
    notify_delay_minutes: Mapped[int] = mapped_column(Integer, default=60)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    user: Mapped["User"] = relationship(back_populates="medication_plans")
    logs: Mapped[list["MedicationLog"]] = relationship(back_populates="plan")


class MedicationLog(Base):
    __tablename__ = "medication_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    plan_id: Mapped[int] = mapped_column(ForeignKey("medication_plans.id"), index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    taken_date: Mapped[date] = mapped_column(Date)
    taken_time: Mapped[time] = mapped_column()
    is_taken: Mapped[bool] = mapped_column(Boolean, default=True)
    checked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    plan: Mapped["MedicationPlan"] = relationship(back_populates="logs")
    user: Mapped["User"] = relationship(back_populates="medication_logs")


class BloodPressureRecord(Base):
    __tablename__ = "blood_pressure_records"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    systolic: Mapped[int] = mapped_column(Integer)
    diastolic: Mapped[int] = mapped_column(Integer)
    heart_rate: Mapped[int | None] = mapped_column(Integer, nullable=True)
    measured_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    user: Mapped["User"] = relationship(back_populates="blood_pressure_records")


class BloodSugarRecord(Base):
    __tablename__ = "blood_sugar_records"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    level: Mapped[float] = mapped_column()
    condition: Mapped[str] = mapped_column(String(64))  # 空腹 / 餐后
    measured_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    user: Mapped["User"] = relationship(back_populates="blood_sugar_records")


class FamilyLink(Base):
    __tablename__ = "family_links"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    elder_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    caregiver_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    status: Mapped[str] = mapped_column(String(32), default="PENDING")
    permissions: Mapped[str] = mapped_column(String(32), default="VIEW_ONLY")
    elder_alias: Mapped[str | None] = mapped_column(String(128), nullable=True)
    caregiver_alias: Mapped[str | None] = mapped_column(String(128), nullable=True)
    receive_weekly_report: Mapped[bool] = mapped_column(Boolean, default=True)

    elder: Mapped["User"] = relationship(back_populates="elder_links", foreign_keys=[elder_id])
    caregiver: Mapped["User"] = relationship(
        back_populates="caregiver_links", foreign_keys=[caregiver_id]
    )


class FamilyLinkActionLog(Base):
    __tablename__ = "family_link_action_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    action: Mapped[str] = mapped_column(String(64), index=True)
    actor_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    elder_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    caregiver_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    link_id: Mapped[int | None] = mapped_column(ForeignKey("family_links.id"), nullable=True, index=True)
    counterpart_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    invite_code: Mapped[str | None] = mapped_column(String(32), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        index=True,
    )


class DeviceToken(Base):
    __tablename__ = "device_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    fcm_token: Mapped[str | None] = mapped_column(String(512), nullable=True, index=True)
    wxpusher_uid: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
    device_label: Mapped[str | None] = mapped_column(String(128), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
    )

    user: Mapped["User"] = relationship(back_populates="device_tokens")


class MedicationPokeEvent(Base):
    __tablename__ = "medication_poke_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    plan_id: Mapped[int] = mapped_column(ForeignKey("medication_plans.id"), index=True)
    caregiver_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        index=True,
    )


class SubscriptionEvent(Base):
    __tablename__ = "subscription_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    app_user_id: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
    revenuecat_event_id: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
    event_type: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    product_id: Mapped[str | None] = mapped_column(String(256), nullable=True)
    entitlement_id: Mapped[str | None] = mapped_column(String(128), nullable=True)
    transaction_id: Mapped[str | None] = mapped_column(String(256), nullable=True, index=True)
    original_transaction_id: Mapped[str | None] = mapped_column(String(256), nullable=True, index=True)
    store: Mapped[str | None] = mapped_column(String(64), nullable=True)
    environment: Mapped[str | None] = mapped_column(String(64), nullable=True)
    purchased_at_ms: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    expiration_at_ms: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    price: Mapped[str | None] = mapped_column(String(64), nullable=True)
    currency: Mapped[str | None] = mapped_column(String(16), nullable=True)
    raw_event: Mapped[str] = mapped_column(Text)
    raw_payload: Mapped[str] = mapped_column(Text)
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        index=True,
    )

    user: Mapped[User | None] = relationship("User", back_populates="subscription_events")

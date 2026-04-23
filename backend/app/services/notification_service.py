import json
import logging
from datetime import date, datetime, time, timedelta

import firebase_admin
from firebase_admin import credentials, messaging
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.models import DeviceToken, FamilyLink, MedicationLog, MedicationPlan, User

logger = logging.getLogger(__name__)
_firebase_ready = False


def _try_init_firebase() -> bool:
    global _firebase_ready
    if _firebase_ready:
        return True
    if not settings.firebase_credentials_path:
        logger.warning("Firebase credentials path not configured; push will be skipped.")
        return False
    try:
        if not firebase_admin._apps:
            cred = credentials.Certificate(settings.firebase_credentials_path)
            firebase_admin.initialize_app(cred)
        _firebase_ready = True
        return True
    except Exception as exc:
        logger.exception("Failed to initialize Firebase Admin: %s", exc)
        return False


def _get_caregiver_users(db: Session, elder_id: int) -> list[User]:
    rows = db.execute(
        select(User)
        .join(FamilyLink, FamilyLink.caregiver_id == User.id)
        .where(
            FamilyLink.elder_id == elder_id,
            FamilyLink.status == "APPROVED",
        )
    ).scalars().all()
    return rows


def _send_fcm_tokens(tokens: list[str], title: str, body: str, data: dict[str, str] | None = None) -> None:
    if not tokens:
        return
    if not _try_init_firebase():
        return
    multicast = messaging.MulticastMessage(
        notification=messaging.Notification(title=title, body=body),
        data=data or {},
        tokens=tokens,
    )
    try:
        resp = messaging.send_each_for_multicast(multicast)
        logger.info("FCM push sent: success=%s failure=%s", resp.success_count, resp.failure_count)
    except Exception as exc:
        logger.exception("FCM send failed: %s", exc)


def send_poke_to_elder(tokens: list[str], title: str, body: str, data: dict[str, str] | None = None) -> None:
    if not tokens:
        return
    if not _try_init_firebase():
        return
    message = messaging.MulticastMessage(
        notification=messaging.Notification(title=title, body=body),
        data=data or {},
        tokens=tokens,
        android=messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id="medication_reminder",
                sound="default",
            ),
        ),
        apns=messaging.APNSConfig(
            headers={"apns-priority": "10"},
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
                    sound="default",
                    content_available=True,
                )
            ),
        ),
    )
    try:
        resp = messaging.send_each_for_multicast(message)
        logger.info("Poke push sent: success=%s failure=%s", resp.success_count, resp.failure_count)
    except Exception as exc:
        logger.exception("Poke push failed: %s", exc)


def notify_caregivers_for_abnormal_vitals(
    db: Session,
    elder_id: int,
    elder_name: str,
    alert_text: str,
    payload: dict[str, str] | None = None,
) -> None:
    caregivers = _get_caregiver_users(db, elder_id)
    if not caregivers:
        return
    caregiver_ids = [row.id for row in caregivers]
    tokens = db.execute(
        select(DeviceToken.fcm_token).where(
            DeviceToken.user_id.in_(caregiver_ids),
            DeviceToken.fcm_token.is_not(None),
        )
    ).scalars().all()
    clean_tokens = [token for token in tokens if token and token.strip()]
    body = f"警报：{elder_name} 的{alert_text}"
    _send_fcm_tokens(
        clean_tokens,
        title="Zellia 异常预警",
        body=body,
        data=payload,
    )


def _parse_time_slot(raw: str) -> time | None:
    value = raw.strip()
    if not value:
        return None
    parts = value.split(":")
    if len(parts) < 2:
        return None
    try:
        hh = int(parts[0])
        mm = int(parts[1])
        return time(hh, mm)
    except ValueError:
        return None


def check_missed_medications(db: Session) -> None:
    now = datetime.now()
    today = date.today()
    one_hour_ago = now - timedelta(hours=1)
    two_hours_ago = now - timedelta(hours=2)
    plans = db.execute(
        select(MedicationPlan).where(
            MedicationPlan.is_active.is_(True),
            MedicationPlan.start_date <= today,
            MedicationPlan.end_date >= today,
        )
    ).scalars().all()

    for plan in plans:
        elder = db.get(User, plan.user_id)
        if elder is None:
            continue
        slots = [slot for slot in plan.times_a_day.split(",") if slot.strip()]
        for slot in slots:
            slot_time = _parse_time_slot(slot)
            if slot_time is None:
                continue
            scheduled_dt = datetime.combine(today, slot_time)
            # send once in a bounded hourly window to avoid repeated spam
            if not (two_hours_ago <= scheduled_dt < one_hour_ago):
                continue
            existing = db.execute(
                select(MedicationLog.id).where(
                    MedicationLog.plan_id == plan.id,
                    MedicationLog.user_id == plan.user_id,
                    MedicationLog.taken_date == today,
                    MedicationLog.taken_time == slot_time,
                    MedicationLog.is_taken.is_(True),
                )
            ).first()
            if existing is not None:
                continue
            alert_body = f"似乎忘记服用 {plan.name}"
            notify_caregivers_for_abnormal_vitals(
                db=db,
                elder_id=plan.user_id,
                elder_name=elder.username,
                alert_text=alert_body,
                payload={
                    "type": "medication_missed",
                    "elder_id": str(plan.user_id),
                    "plan_id": str(plan.id),
                    "slot": slot_time.strftime("%H:%M"),
                },
            )
            logger.info(
                "Missed medication alert sent: %s",
                json.dumps(
                    {
                        "elder_id": plan.user_id,
                        "plan_id": plan.id,
                        "slot": slot_time.strftime("%H:%M"),
                    },
                    ensure_ascii=False,
                ),
            )

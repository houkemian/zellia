import json
import logging
from datetime import date, datetime, time, timedelta, timezone

from firebase_admin import messaging
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.firebase_app import ensure_firebase_app_ready
from app.models import DeviceToken, FamilyLink, MedicationLog, MedicationPlan, User

logger = logging.getLogger(__name__)
_firebase_ready = False


def _try_init_firebase() -> bool:
    global _firebase_ready
    if _firebase_ready:
        return True
    ok = ensure_firebase_app_ready()
    if ok:
        _firebase_ready = True
    else:
        logger.warning(
            "Firebase is not configured (need FIREBASE_CREDENTIALS_PATH or FIREBASE_PROJECT_ID); push will be skipped."
        )
    return ok


def _caregiver_fcm_tokens(db: Session, elder_id: int) -> list[str]:
    rows = db.execute(
        select(DeviceToken.fcm_token)
        .join(FamilyLink, FamilyLink.caregiver_id == DeviceToken.user_id)
        .where(
            FamilyLink.elder_id == elder_id,
            FamilyLink.status == "APPROVED",
            DeviceToken.fcm_token.is_not(None),
        )
    ).scalars().all()
    return [token for token in rows if token and str(token).strip()]


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
    # Data-only so the app shows the notification with cached family voice m4a
    # (system FCM notification payload always uses default sound).
    payload = dict(data or {})
    payload["title"] = title
    payload["body"] = body
    message = messaging.MulticastMessage(
        data={k: str(v) for k, v in payload.items()},
        tokens=tokens,
        android=messaging.AndroidConfig(priority="high"),
        apns=messaging.APNSConfig(
            headers={"apns-priority": "10"},
            payload=messaging.APNSPayload(
                aps=messaging.Aps(
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


def _caregiver_tokens_for_elder(db: Session, elder_id: int, caregiver_id: int) -> list[str]:
    rows = db.execute(
        select(DeviceToken.fcm_token).where(
            DeviceToken.user_id == caregiver_id,
            DeviceToken.fcm_token.is_not(None),
        )
    ).scalars().all()
    if not rows:
        return []
    link_ok = db.execute(
        select(FamilyLink.id).where(
            FamilyLink.elder_id == elder_id,
            FamilyLink.caregiver_id == caregiver_id,
            FamilyLink.status == "APPROVED",
        )
    ).first()
    if link_ok is None:
        return []
    return [token for token in rows if token and str(token).strip()]


def notify_caregivers_weekly_summary(
    db: Session,
    elder_id: int,
    caregiver_id: int,
    body: str,
    week_start: str,
) -> None:
    try:
        tokens = _caregiver_tokens_for_elder(db, elder_id, caregiver_id)
    except Exception as exc:
        logger.exception("weekly summary: token lookup failed: %s", exc)
        return
    if not tokens:
        return
    _send_fcm_tokens(
        tokens,
        title="Zellia 本周健康总结",
        body=body,
        data={
            "action": "open_weekly_summary",
            "elder_id": str(elder_id),
            "week_start": week_start,
        },
    )


def notify_caregivers_for_abnormal_vitals(
    db: Session,
    elder_id: int,
    elder_name: str,
    alert_text: str,
    payload: dict[str, str] | None = None,
) -> None:
    try:
        clean_tokens = _caregiver_fcm_tokens(db, elder_id)
    except Exception as exc:
        logger.exception("notify_caregivers_for_abnormal_vitals: token lookup failed: %s", exc)
        return
    if not clean_tokens:
        return
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
    # Wall-clock slots are compared in UTC; elder-local TZ would need per-user offset.
    now = datetime.now(timezone.utc)
    today = now.date()
    one_hour_ago = now - timedelta(hours=1)
    two_hours_ago = now - timedelta(hours=2)
    plans = db.execute(
        select(MedicationPlan).where(
            MedicationPlan.is_active.is_(True),
            MedicationPlan.start_date <= today,
            MedicationPlan.end_date >= today,
        )
    ).scalars().all()
    if not plans:
        return

    user_ids = list({plan.user_id for plan in plans})
    elders = db.execute(select(User).where(User.id.in_(user_ids))).scalars().all()
    user_map = {user.id: user for user in elders}

    plan_ids = [plan.id for plan in plans]
    taken_rows = db.execute(
        select(MedicationLog.plan_id, MedicationLog.taken_time).where(
            MedicationLog.taken_date == today,
            MedicationLog.is_taken.is_(True),
            MedicationLog.cancelled_at.is_(None),
            MedicationLog.plan_id.in_(plan_ids),
        )
    ).all()
    taken_slots = {(plan_id, taken_time) for plan_id, taken_time in taken_rows}

    for plan in plans:
        elder = user_map.get(plan.user_id)
        if elder is None:
            continue
        slots = [slot for slot in plan.times_a_day.split(",") if slot.strip()]
        for slot in slots:
            slot_time = _parse_time_slot(slot)
            if slot_time is None:
                continue
            scheduled_dt = datetime.combine(today, slot_time, tzinfo=timezone.utc)
            # send once in a bounded hourly window to avoid repeated spam
            if not (two_hours_ago <= scheduled_dt < one_hour_ago):
                continue
            if (plan.id, slot_time) in taken_slots:
                continue
            alert_body = f"似乎忘记服用 {plan.name}"
            elder_display = (elder.nickname or "").strip() or elder.username
            notify_caregivers_for_abnormal_vitals(
                db=db,
                elder_id=plan.user_id,
                elder_name=elder_display,
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

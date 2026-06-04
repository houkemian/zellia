import json
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.models import SubscriptionEvent, User

router = APIRouter(tags=["webhooks"])

_PREMIUM_ON = frozenset({"INITIAL_PURCHASE", "RENEWAL"})
_PREMIUM_OFF = frozenset({"CANCELLATION", "EXPIRATION"})


def _authorization_matches_secret(authorization: str | None, secret: str) -> bool:
    if authorization is None or not authorization.strip():
        return False
    auth = authorization.strip()
    expected = secret.strip()
    if auth == expected:
        return True
    prefix = "Bearer "
    if auth.lower().startswith(prefix.lower()):
        return auth[len(prefix) :].strip() == expected
    return False


def _json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), default=str)


def _event_str(event: dict[str, Any], key: str) -> str | None:
    value = event.get(key)
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _event_int(event: dict[str, Any], key: str) -> int | None:
    value = event.get(key)
    if value is None or value == "":
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _event_type(payload: dict[str, Any], event: dict[str, Any]) -> str | None:
    value = event.get("type") or payload.get("type")
    if value is None:
        return None
    text = str(value).strip().upper()
    return text or None


def _ms_to_datetime(value: int | None) -> datetime | None:
    if value is None:
        return None
    try:
        return datetime.fromtimestamp(value / 1000, tz=timezone.utc)
    except (OverflowError, OSError, ValueError):
        return None


def _aware_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _is_stale_subscription_event(
    user: User,
    *,
    event_type: str | None,
    expiration_dt: datetime | None,
) -> bool:
    if event_type not in _PREMIUM_ON and event_type not in _PREMIUM_OFF:
        return False
    current_expiry = _aware_utc(user.premium_expires_at)
    if current_expiry is None or expiration_dt is None:
        return False
    # RevenueCat may retry or deliver old lifecycle events after a later renewal.
    # Never let an event with an older entitlement expiry reduce a newer local expiry.
    return expiration_dt < current_expiry


def _subscription_state_for_event(
    *,
    event_type: str | None,
    expiration_dt: datetime | None,
) -> bool | None:
    now = datetime.now(timezone.utc)
    if event_type in _PREMIUM_ON:
        return expiration_dt is None or expiration_dt > now
    if event_type in _PREMIUM_OFF:
        if expiration_dt is not None:
            return expiration_dt > now
        return False if event_type == "EXPIRATION" else None
    return None


def _record_subscription_event(
    db: Session,
    *,
    payload: dict[str, Any],
    event: dict[str, Any],
    event_type: str | None,
    app_user_id: str | None,
    user_id: int | None,
) -> SubscriptionEvent:
    record = SubscriptionEvent(
        user_id=user_id,
        app_user_id=app_user_id,
        revenuecat_event_id=_event_str(event, "id"),
        event_type=event_type,
        product_id=_event_str(event, "product_id"),
        entitlement_id=_event_str(event, "entitlement_id"),
        transaction_id=_event_str(event, "transaction_id"),
        original_transaction_id=_event_str(event, "original_transaction_id"),
        store=_event_str(event, "store"),
        environment=_event_str(event, "environment"),
        purchased_at_ms=_event_int(event, "purchased_at_ms"),
        expiration_at_ms=_event_int(event, "expiration_at_ms"),
        price=_event_str(event, "price"),
        currency=_event_str(event, "currency"),
        raw_event=_json_dumps(event),
        raw_payload=_json_dumps(payload),
    )
    db.add(record)
    return record


@router.post("/webhooks/revenuecat")
async def revenuecat_webhook(
    request: Request,
    db: Session = Depends(get_db),
    authorization: str | None = Header(None, alias="Authorization"),
) -> dict[str, Any]:
    secret = (settings.revenuecat_webhook_secret or "").strip()
    if not secret:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="RevenueCat webhook is not configured",
        )
    if not _authorization_matches_secret(authorization, secret):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing Authorization",
        )

    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid JSON body")
    if not isinstance(payload, dict):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid JSON payload")

    event = payload.get("event")
    if not isinstance(event, dict):
        event = {}

    event_type = _event_type(payload, event)
    event_id = _event_str(event, "id")
    if event_id:
        existing_event = db.execute(
            select(SubscriptionEvent.id).where(
                SubscriptionEvent.revenuecat_event_id == event_id,
            )
        ).first()
        if existing_event is not None:
            return {"ok": True, "duplicate": True, "revenuecat_event_id": event_id}

    app_user_id_raw = event.get("app_user_id") or payload.get("app_user_id")
    app_user_id = str(app_user_id_raw).strip() if app_user_id_raw is not None else None
    if app_user_id_raw is None or (isinstance(app_user_id_raw, str) and not app_user_id_raw.strip()):
        _record_subscription_event(
            db,
            payload=payload,
            event=event,
            event_type=event_type,
            app_user_id=app_user_id,
            user_id=None,
        )
        db.commit()
        return {"ok": True, "ignored": True, "reason": "missing_app_user_id"}

    try:
        user_id = int(str(app_user_id_raw).strip())
    except ValueError:
        _record_subscription_event(
            db,
            payload=payload,
            event=event,
            event_type=event_type,
            app_user_id=app_user_id,
            user_id=None,
        )
        db.commit()
        return {"ok": True, "ignored": True, "reason": "invalid_app_user_id"}

    user = db.get(User, user_id)
    _record_subscription_event(
        db,
        payload=payload,
        event=event,
        event_type=event_type,
        app_user_id=app_user_id,
        user_id=user_id if user is not None else None,
    )
    if user is None:
        db.commit()
        return {"ok": True, "ignored": True, "reason": "user_not_found"}

    expiration_dt = _ms_to_datetime(_event_int(event, "expiration_at_ms"))
    state = _subscription_state_for_event(event_type=event_type, expiration_dt=expiration_dt)
    stale = _is_stale_subscription_event(
        user,
        event_type=event_type,
        expiration_dt=expiration_dt,
    )

    if state is not None and not stale:
        user.is_premium = state
        if expiration_dt is not None:
            user.premium_expires_at = expiration_dt
        elif event_type == "EXPIRATION":
            user.premium_expires_at = datetime.now(timezone.utc)

    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        if event_id:
            return {"ok": True, "duplicate": True, "revenuecat_event_id": event_id}
        raise

    if state is not None:
        return {
            "ok": True,
            "updated": not stale,
            "ignored": stale,
            "reason": "stale_event" if stale else None,
            "is_premium": bool(user.is_premium),
            "event_type": event_type,
            "premium_expires_at": user.premium_expires_at.isoformat()
            if user.premium_expires_at is not None
            else None,
        }

    return {"ok": True, "ignored": True, "reason": "event_type_not_handled", "event_type": event_type}

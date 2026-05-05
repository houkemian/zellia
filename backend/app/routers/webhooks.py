from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.dependencies import _ensure_user_profile_columns
from app.models import User

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

    _ensure_user_profile_columns(db)

    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid JSON body")

    event = payload.get("event")
    if not isinstance(event, dict):
        event = {}

    event_type = (event.get("type") or payload.get("type") or "").strip().upper()
    app_user_id_raw = event.get("app_user_id") or payload.get("app_user_id")

    if app_user_id_raw is None or (isinstance(app_user_id_raw, str) and not app_user_id_raw.strip()):
        return {"ok": True, "ignored": True, "reason": "missing_app_user_id"}

    try:
        user_id = int(str(app_user_id_raw).strip())
    except ValueError:
        return {"ok": True, "ignored": True, "reason": "invalid_app_user_id"}

    user = db.get(User, user_id)
    if user is None:
        return {"ok": True, "ignored": True, "reason": "user_not_found"}

    if event_type in _PREMIUM_ON:
        user.is_premium = True
        db.commit()
        return {"ok": True, "updated": True, "is_premium": True, "event_type": event_type}

    if event_type in _PREMIUM_OFF:
        user.is_premium = False
        db.commit()
        return {"ok": True, "updated": True, "is_premium": False, "event_type": event_type}

    return {"ok": True, "ignored": True, "reason": "event_type_not_handled", "event_type": event_type or None}

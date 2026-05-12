"""Single place to initialize Firebase Admin (verify tokens, custom tokens, FCM)."""

from __future__ import annotations

import logging
import os
from pathlib import Path

import firebase_admin
from firebase_admin import credentials

from app.config import settings

logger = logging.getLogger(__name__)


def resolve_firebase_credentials_path() -> str | None:
    """Path from settings or process env; normalized. Settings may miss if .env was loaded from wrong CWD."""
    raw = settings.firebase_credentials_path or os.getenv("FIREBASE_CREDENTIALS_PATH")
    if raw is None:
        return None
    s = str(raw).strip()
    if not s:
        return None
    s = os.path.expanduser(s)
    return s


def ensure_firebase_app_ready(fallback_project_id: str | None = None) -> bool:
    """Initialize default Firebase app if missing. Returns False on misconfiguration or errors."""
    try:
        if firebase_admin._apps:
            return True
        project_id = (
            settings.firebase_project_id
            or os.getenv("GOOGLE_CLOUD_PROJECT")
            or os.getenv("GCP_PROJECT")
            or fallback_project_id
        )
        cred_path = resolve_firebase_credentials_path()
        if cred_path:
            p = Path(cred_path)
            if not p.is_file():
                logger.error("FIREBASE_CREDENTIALS_PATH is not a readable file: %s", p.resolve())
                return False
            cred = credentials.Certificate(str(p))
            firebase_admin.initialize_app(cred)
        elif project_id:
            try:
                adc = credentials.ApplicationDefault()
                firebase_admin.initialize_app(adc, {"projectId": project_id})
            except Exception:
                firebase_admin.initialize_app(options={"projectId": project_id})
        else:
            try:
                adc = credentials.ApplicationDefault()
                firebase_admin.initialize_app(adc)
            except Exception:
                logger.warning(
                    "Firebase not configured: set FIREBASE_CREDENTIALS_PATH or FIREBASE_PROJECT_ID / GOOGLE_CLOUD_PROJECT"
                )
                return False
        return True
    except Exception as exc:
        logger.exception("Firebase Admin initialization failed: %s", exc)
        return False

"""Single place to initialize Firebase Admin (verify tokens, custom tokens, FCM)."""

from __future__ import annotations

import logging
import os
from pathlib import Path

import firebase_admin
from firebase_admin import credentials

from app.config import BACKEND_ROOT, settings

logger = logging.getLogger(__name__)


def _strip_env_value(value: str) -> str:
    """Strip whitespace and optional surrounding quotes from .env / systemd values."""
    s = str(value).strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
        s = s[1:-1].strip()
    return s


def _credential_path_candidates(declared: str) -> list[Path]:
    """Try declared path, then same filename under backend/ and repo root (common deploy layouts)."""
    base = Path(os.path.expanduser(_strip_env_value(declared))).expanduser()
    out: list[Path] = []
    seen: set[str] = set()

    def add(p: Path) -> None:
        try:
            resolved = p.resolve(strict=False)
        except OSError:
            resolved = p
        key = str(resolved)
        if key not in seen:
            seen.add(key)
            out.append(resolved)

    add(base)
    if base.name and base.name.endswith(".json"):
        add(BACKEND_ROOT / base.name)
        add(BACKEND_ROOT.parent / base.name)
    if not base.is_absolute():
        add((BACKEND_ROOT / base).resolve(strict=False))
        add((BACKEND_ROOT.parent / base).resolve(strict=False))
        add(Path.cwd() / base)
    return out


def resolve_firebase_credentials_path() -> str | None:
    """Return a readable service-account JSON path, or None."""
    raw = settings.firebase_credentials_path or os.getenv("FIREBASE_CREDENTIALS_PATH")
    if raw is None:
        return None
    s = _strip_env_value(str(raw))
    if not s:
        return None

    for candidate in _credential_path_candidates(s):
        if candidate.is_file():
            return str(candidate)

    primary = Path(os.path.expanduser(s)).expanduser()
    try:
        resolved = primary.resolve(strict=False)
    except OSError:
        resolved = primary
    logger.error(
        "FIREBASE_CREDENTIALS_PATH is not a readable file. Declared=%r resolved=%r "
        "exists=%s is_dir=%s readable=%s cwd=%s backend_root=%s backend_candidate=%s",
        raw,
        str(resolved),
        resolved.exists(),
        resolved.is_dir(),
        os.access(resolved, os.R_OK) if resolved.exists() else False,
        str(Path.cwd()),
        str(BACKEND_ROOT),
        str(BACKEND_ROOT / Path(s).name) if Path(s).name else "",
    )
    return None


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
        declared_raw = settings.firebase_credentials_path or os.getenv("FIREBASE_CREDENTIALS_PATH")
        cred_path = resolve_firebase_credentials_path()
        if cred_path:
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
        elif declared_raw and _strip_env_value(str(declared_raw)) and not cred_path:
            return False
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

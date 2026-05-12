"""Single place to initialize Firebase Admin (verify tokens, custom tokens, FCM)."""

from __future__ import annotations

import json
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


def _in_dockerish_runtime() -> bool:
    return Path("/.dockerenv").is_file() or os.getenv("container") == "oci"


def _credential_path_candidates(declared: str) -> list[Path]:
    """Try declared path, then common container / monorepo locations."""
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
        if BACKEND_ROOT.parent != BACKEND_ROOT and str(BACKEND_ROOT.parent) not in {".", "/"}:
            add(BACKEND_ROOT.parent / base.name)
        add(Path("/run/secrets") / base.name)
    if not base.is_absolute():
        add((BACKEND_ROOT / base).resolve(strict=False))
        if BACKEND_ROOT.parent != BACKEND_ROOT and str(BACKEND_ROOT.parent) not in {".", "/"}:
            add((BACKEND_ROOT.parent / base).resolve(strict=False))
        add(Path.cwd() / base)
    return out


def _certificate_from_json_env() -> credentials.Certificate | None:
    raw = os.getenv("FIREBASE_CREDENTIALS_JSON")
    if not raw:
        return None
    s = _strip_env_value(raw)
    if not s:
        return None
    try:
        info = json.loads(s)
        if not isinstance(info, dict):
            logger.error("FIREBASE_CREDENTIALS_JSON must be a JSON object")
            return None
        return credentials.Certificate(info)
    except json.JSONDecodeError as exc:
        logger.error("FIREBASE_CREDENTIALS_JSON is not valid JSON: %s", exc)
        return None
    except Exception as exc:
        logger.exception("FIREBASE_CREDENTIALS_JSON could not be loaded: %s", exc)
        return None


def _certificate_from_declared_path(
    raw: str | None, *, env_label: str = "FIREBASE_CREDENTIALS_PATH"
) -> credentials.Certificate | None:
    if raw is None:
        return None
    s = _strip_env_value(str(raw))
    if not s:
        return None

    for candidate in _credential_path_candidates(s):
        if candidate.is_file():
            try:
                return credentials.Certificate(str(candidate))
            except Exception as exc:
                logger.error("Invalid Firebase service account file %s: %s", candidate, exc)
                return None

    primary = Path(os.path.expanduser(s)).expanduser()
    try:
        resolved = primary.resolve(strict=False)
    except OSError:
        resolved = primary

    hint = ""
    if _in_dockerish_runtime() and str(resolved).startswith(("/home/", "/Users/")):
        hint = (
            " Inside Docker, host paths are not mounted unless you configure a volume. "
            "Options: (1) mount the JSON into the container and set FIREBASE_CREDENTIALS_PATH "
            "to the in-container path (e.g. /app/secrets/firebase.json); "
            "(2) set FIREBASE_CREDENTIALS_JSON to the full service-account JSON; "
            "(3) set GOOGLE_APPLICATION_CREDENTIALS to a path inside the container."
        )

    logger.error(
        "%s is not a readable file. Declared=%r resolved=%r "
        "exists=%s is_dir=%s readable=%s cwd=%s backend_root=%s backend_candidate=%s.%s",
        env_label,
        raw,
        str(resolved),
        resolved.exists(),
        resolved.is_dir(),
        os.access(resolved, os.R_OK) if resolved.exists() else False,
        str(Path.cwd()),
        str(BACKEND_ROOT),
        str(BACKEND_ROOT / Path(s).name) if Path(s).name else "",
        hint,
    )
    return None


def load_firebase_service_account_certificate() -> credentials.Certificate | None:
    """Prefer inline JSON (Docker/K8s), then GOOGLE_APPLICATION_CREDENTIALS, then FIREBASE_CREDENTIALS_PATH."""
    cert = _certificate_from_json_env()
    if cert is not None:
        return cert

    gac = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
    if gac:
        cert = _certificate_from_declared_path(gac, env_label="GOOGLE_APPLICATION_CREDENTIALS")
        if cert is not None:
            return cert

    raw = settings.firebase_credentials_path or os.getenv("FIREBASE_CREDENTIALS_PATH")
    return _certificate_from_declared_path(raw)


def resolve_firebase_credentials_path() -> str | None:
    """Return a readable service-account JSON path, or None (no inline JSON handling)."""
    raw = settings.firebase_credentials_path or os.getenv("FIREBASE_CREDENTIALS_PATH")
    if raw is None:
        return None
    s = _strip_env_value(str(raw))
    if not s:
        return None
    for candidate in _credential_path_candidates(s):
        if candidate.is_file():
            return str(candidate)
    return None


def _user_declared_path_credentials() -> bool:
    raw = settings.firebase_credentials_path or os.getenv("FIREBASE_CREDENTIALS_PATH")
    return bool(raw and _strip_env_value(str(raw)))


def _user_declared_json_credentials() -> bool:
    raw = os.getenv("FIREBASE_CREDENTIALS_JSON")
    return bool(raw and _strip_env_value(raw))


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

        cert = load_firebase_service_account_certificate()
        if cert is not None:
            firebase_admin.initialize_app(cert)
            return True

        if _user_declared_json_credentials() or _user_declared_path_credentials():
            return False

        if project_id:
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
                    "Firebase not configured: set FIREBASE_CREDENTIALS_JSON, "
                    "FIREBASE_CREDENTIALS_PATH (in-container path), GOOGLE_APPLICATION_CREDENTIALS, "
                    "or FIREBASE_PROJECT_ID / GOOGLE_CLOUD_PROJECT with ADC"
                )
                return False
        return True
    except Exception as exc:
        logger.exception("Firebase Admin initialization failed: %s", exc)
        return False

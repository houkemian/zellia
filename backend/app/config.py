import os
from pathlib import Path

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Resolve backend/.env regardless of process cwd (systemd, docker, uvicorn from repo root).
BACKEND_ROOT = Path(__file__).resolve().parent.parent


def _env_file_tuple() -> tuple[Path | str, ...]:
    paths: list[Path] = []
    backend_env = BACKEND_ROOT / ".env"
    if backend_env.is_file():
        paths.append(backend_env)
    cwd_env = Path.cwd() / ".env"
    try:
        if cwd_env.is_file() and cwd_env.resolve() != backend_env.resolve():
            paths.append(cwd_env)
    except OSError:
        pass
    return tuple(paths)


_env_cfg: dict = {"extra": "ignore"}
_env_files = _env_file_tuple()
if _env_files:
    _env_cfg["env_file"] = _env_files
    _env_cfg["env_file_encoding"] = "utf-8"

DEFAULT_SECRET_KEY = "change-me-in-production-use-env"
INSECURE_SECRET_KEYS = {DEFAULT_SECRET_KEY, "replace-with-a-secure-random-string"}
PRODUCTION_ENVS = {"prod", "production"}


class Settings(BaseSettings):
    model_config = SettingsConfigDict(**_env_cfg)

    app_name: str = "Zellia API"
    zellia_env: str = "local"
    secret_key: str = DEFAULT_SECRET_KEY
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7
    database_url: str = "sqlite:///./ever_well.db"
    redis_url: str = "redis://localhost:6379/0"
    firebase_credentials_path: str | None = None
    firebase_project_id: str | None = None
    revenuecat_webhook_secret: str | None = None

    # Cloudflare R2 (S3-compatible) for PRO family voice reminders.
    r2_account_id: str | None = None
    r2_access_key_id: str | None = None
    r2_secret_access_key: str | None = None
    r2_bucket_name: str | None = None
    r2_public_base_url: str | None = None

    # Caregiver poke elder: Redis lock TTL seconds; set 0 to disable (testing only).
    medication_poke_cooldown_seconds: int = 600

    # Slow-request trap: log / optionally write PyInstrument HTML when duration exceeds threshold.
    slow_request_threshold: float = 2.0
    # When False (default), only log slow requests — no per-request profiler overhead.
    enable_slow_request_profiling: bool = False

    @field_validator("zellia_env", mode="before")
    @classmethod
    def _normalize_zellia_env(cls, v: object) -> str:
        if v is None:
            return "local"
        s = str(v).strip().lower()
        return s or "local"

    @field_validator("secret_key", mode="before")
    @classmethod
    def _strip_secret_key(cls, v: object) -> str:
        if v is None:
            return DEFAULT_SECRET_KEY
        s = str(v).strip()
        if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
            s = s[1:-1].strip()
        return s or DEFAULT_SECRET_KEY

    @model_validator(mode="after")
    def _validate_production_secrets(self) -> "Settings":
        if self.zellia_env not in PRODUCTION_ENVS:
            return self
        if self.secret_key in INSECURE_SECRET_KEYS or len(self.secret_key) < 32:
            raise ValueError(
                "SECRET_KEY must be set to a secure value of at least 32 characters "
                "when ZELLIA_ENV is production"
            )
        if not self.firebase_project_id:
            raise ValueError("FIREBASE_PROJECT_ID must be set when ZELLIA_ENV is production")
        return self

    @field_validator("firebase_credentials_path", mode="before")
    @classmethod
    def _normalize_firebase_credentials_path(cls, v: object) -> str | None:
        if v is None:
            return None
        s = str(v).strip()
        if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
            s = s[1:-1].strip()
        if not s:
            return None
        return os.path.expanduser(s)

    @field_validator("firebase_project_id", mode="before")
    @classmethod
    def _strip_optional_project_id(cls, v: object) -> str | None:
        if v is None:
            return None
        s = str(v).strip()
        return s or None


settings = Settings()

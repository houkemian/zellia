import os
from pathlib import Path

from pydantic import field_validator
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


class Settings(BaseSettings):
    model_config = SettingsConfigDict(**_env_cfg)

    app_name: str = "Zellia API"
    secret_key: str = "change-me-in-production-use-env"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7
    database_url: str = "sqlite:///./ever_well.db"
    redis_url: str = "redis://localhost:6379/0"
    firebase_credentials_path: str | None = None
    firebase_project_id: str | None = None
    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_username: str | None = None
    smtp_password: str | None = None
    smtp_from_email: str | None = None
    smtp_use_tls: bool = True
    revenuecat_webhook_secret: str | None = None

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

"""Run Alembic migrations (replaces runtime schema_bootstrap / ALTER TABLE)."""

from __future__ import annotations

import logging
import os
from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import inspect

from app.database import engine

logger = logging.getLogger(__name__)

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
_INITIAL_REVISION = "d4cf556a873d"


def _alembic_config() -> Config:
    cfg = Config(str(_BACKEND_ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(_BACKEND_ROOT / "alembic"))
    return cfg


def _has_table(table_name: str) -> bool:
    try:
        return inspect(engine).has_table(table_name)
    except Exception as exc:
        logger.warning("Could not inspect table %s: %s", table_name, exc)
        return False


def _stamp_legacy_schema_if_needed(cfg: Config) -> None:
    """DBs created by schema_bootstrap have tables but no alembic_version row."""
    if not _has_table("users"):
        return
    if _has_table("alembic_version"):
        return
    logger.warning(
        "Detected existing schema without alembic_version; stamping %s before upgrade",
        _INITIAL_REVISION,
    )
    os.environ["ALEMBIC_SKIP_FILECONFIG"] = "1"
    try:
        command.stamp(cfg, _INITIAL_REVISION)
    finally:
        os.environ.pop("ALEMBIC_SKIP_FILECONFIG", None)


def run_alembic_upgrade(revision: str = "head") -> None:
    cfg = _alembic_config()
    _stamp_legacy_schema_if_needed(cfg)
    logger.info("Running Alembic upgrade to %s", revision)
    os.environ["ALEMBIC_SKIP_FILECONFIG"] = "1"
    try:
        command.upgrade(cfg, revision)
    finally:
        os.environ.pop("ALEMBIC_SKIP_FILECONFIG", None)
    logger.info("Alembic upgrade to %s completed", revision)

"""Run Alembic migrations (replaces runtime schema_bootstrap / ALTER TABLE)."""

from __future__ import annotations

import logging
from pathlib import Path

from alembic import command
from alembic.config import Config

logger = logging.getLogger(__name__)

_BACKEND_ROOT = Path(__file__).resolve().parent.parent


def run_alembic_upgrade(revision: str = "head") -> None:
    cfg = Config(str(_BACKEND_ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(_BACKEND_ROOT / "alembic"))
    logger.info("Running Alembic upgrade to %s", revision)
    command.upgrade(cfg, revision)

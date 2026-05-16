"""One-time per-process schema checks (avoid inspect/ALTER on every authenticated request)."""

import logging
import threading

from sqlalchemy import inspect, text
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

_lock = threading.Lock()
_user_profile_columns_done = False
_medication_notify_columns_done = False
_medication_checked_at_done = False
_vitals_indexes_done = False


def _ensure_user_profile_columns_impl(db: Session) -> None:
    columns = {col["name"] for col in inspect(db.bind).get_columns("users")}
    if "nickname" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN nickname VARCHAR(128)"))
        db.commit()
    if "email" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN email VARCHAR(256)"))
        db.commit()
        db.execute(text("CREATE INDEX IF NOT EXISTS ix_users_email ON users (email)"))
        db.commit()
    if "avatar_url" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN avatar_url VARCHAR(512)"))
        db.commit()
    if "is_active" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN is_active BOOLEAN DEFAULT TRUE"))
        db.commit()
    if "is_proxy" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN is_proxy BOOLEAN DEFAULT FALSE"))
        db.commit()
    if "invite_code" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN invite_code VARCHAR(32)"))
        db.commit()
        db.execute(text("CREATE UNIQUE INDEX IF NOT EXISTS ix_users_invite_code ON users (invite_code)"))
        db.commit()
    if "activation_code" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN activation_code VARCHAR(10)"))
        db.commit()
        db.execute(text("CREATE INDEX IF NOT EXISTS ix_users_activation_code ON users (activation_code)"))
        db.commit()
    if "activation_expires_at" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN activation_expires_at TIMESTAMP"))
        db.commit()
    if "is_premium" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN is_premium BOOLEAN DEFAULT FALSE"))
        db.commit()
        db.execute(text("UPDATE users SET is_premium = FALSE WHERE is_premium IS NULL"))
        db.commit()
    if "premium_expires_at" not in columns:
        db.execute(text("ALTER TABLE users ADD COLUMN premium_expires_at TIMESTAMP WITH TIME ZONE"))
        db.commit()


def _ensure_medication_notify_columns_impl(db: Session) -> None:
    columns = {col["name"] for col in inspect(db.bind).get_columns("medication_plans")}
    if "notify_missed" not in columns:
        db.execute(text("ALTER TABLE medication_plans ADD COLUMN notify_missed BOOLEAN DEFAULT TRUE"))
        db.commit()
        db.execute(text("UPDATE medication_plans SET notify_missed = TRUE WHERE notify_missed IS NULL"))
        db.commit()
    if "notify_delay_minutes" not in columns:
        db.execute(text("ALTER TABLE medication_plans ADD COLUMN notify_delay_minutes INTEGER DEFAULT 60"))
        db.commit()
        db.execute(text("UPDATE medication_plans SET notify_delay_minutes = 60 WHERE notify_delay_minutes IS NULL"))
        db.commit()


def _ensure_medication_checked_at_impl(db: Session) -> None:
    columns = {col["name"] for col in inspect(db.bind).get_columns("medication_logs")}
    if "checked_at" in columns:
        return
    db.execute(text("ALTER TABLE medication_logs ADD COLUMN checked_at TIMESTAMP WITH TIME ZONE"))
    db.commit()


def _ensure_vitals_indexes_impl(db: Session) -> None:
    db.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_blood_pressure_user_measured "
            "ON blood_pressure_records (user_id, measured_at DESC)"
        )
    )
    db.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_blood_sugar_user_measured "
            "ON blood_sugar_records (user_id, measured_at DESC)"
        )
    )
    db.commit()


def ensure_user_profile_columns(db: Session) -> None:
    global _user_profile_columns_done
    if _user_profile_columns_done:
        return
    with _lock:
        if _user_profile_columns_done:
            return
        try:
            _ensure_user_profile_columns_impl(db)
            _user_profile_columns_done = True
            logger.info("schema_bootstrap: user_profile_columns completed")
        except Exception as exc:
            logger.exception("schema_bootstrap: user_profile_columns failed: %s", exc)
            try:
                db.rollback()
            except Exception:
                pass
            raise


def ensure_medication_notify_columns(db: Session) -> None:
    global _medication_notify_columns_done
    if _medication_notify_columns_done:
        return
    with _lock:
        if _medication_notify_columns_done:
            return
        try:
            _ensure_medication_notify_columns_impl(db)
            _medication_notify_columns_done = True
            logger.info("schema_bootstrap: medication_notify_columns completed")
        except Exception as exc:
            logger.exception("schema_bootstrap: medication_notify_columns failed: %s", exc)
            try:
                db.rollback()
            except Exception:
                pass
            raise


def ensure_medication_checked_at_column(db: Session) -> None:
    global _medication_checked_at_done
    if _medication_checked_at_done:
        return
    with _lock:
        if _medication_checked_at_done:
            return
        try:
            _ensure_medication_checked_at_impl(db)
            _medication_checked_at_done = True
            logger.info("schema_bootstrap: medication_checked_at completed")
        except Exception as exc:
            logger.exception("schema_bootstrap: medication_checked_at failed: %s", exc)
            try:
                db.rollback()
            except Exception:
                pass
            raise


def ensure_vitals_indexes(db: Session) -> None:
    global _vitals_indexes_done
    if _vitals_indexes_done:
        return
    with _lock:
        if _vitals_indexes_done:
            return
        try:
            _ensure_vitals_indexes_impl(db)
            _vitals_indexes_done = True
            logger.info("schema_bootstrap: vitals_indexes completed")
        except Exception as exc:
            logger.exception("schema_bootstrap: vitals_indexes failed: %s", exc)
            try:
                db.rollback()
            except Exception:
                pass
            raise


def bootstrap_all_schemas(db: Session) -> None:
    """Run at app startup so hot paths like GET /vitals/bp skip DDL in get_current_user."""
    try:
        ensure_user_profile_columns(db)
        ensure_medication_notify_columns(db)
        ensure_medication_checked_at_column(db)
        ensure_vitals_indexes(db)
    except Exception as exc:
        logger.warning("schema_bootstrap at startup partial failure: %s", exc)

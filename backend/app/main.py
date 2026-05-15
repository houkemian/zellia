import logging
import re
from contextlib import asynccontextmanager
from datetime import datetime
from time import perf_counter

import anyio
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from apscheduler.schedulers.background import BackgroundScheduler
from pyinstrument import Profiler
from redis import Redis
from sqlalchemy import text
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from app.config import BACKEND_ROOT, settings
from app.database import Base, SessionLocal, engine
from app.routers import auth, family, medications, notifications, pro_share, reports, vitals, webhooks
from app.services.notification_service import check_missed_medications
from app.services.weekly_digest_service import send_weekly_digests

logger = logging.getLogger(__name__)
scheduler = BackgroundScheduler()

PROFILES_DIR = BACKEND_ROOT / "profiles"


def _sanitize_path_segment(segment: str) -> str:
    cleaned = re.sub(r"[^\w\-]", "_", segment.strip())
    return cleaned or "segment"


def _build_profile_filename(method: str, path: str, duration: float) -> str:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    method_part = _sanitize_path_segment(method.upper())
    segments = [s for s in path.strip("/").split("/") if s]
    if segments:
        path_part = "_".join(_sanitize_path_segment(s) for s in segments)
        if len(path_part) > 120:
            path_part = path_part[:120]
    else:
        path_part = "root"
    duration_part = f"{duration:.1f}s"
    return f"{timestamp}_{method_part}_{path_part}_{duration_part}.html"


def _write_slow_request_profile(profiler: Profiler, request: Request, duration: float) -> None:
    try:
        PROFILES_DIR.mkdir(parents=True, exist_ok=True)
        filename = _build_profile_filename(request.method, request.url.path, duration)
        output_path = PROFILES_DIR / filename
        output_path.write_text(profiler.output_html(), encoding="utf-8")
        logger.warning(
            "Slow request captured (%.2fs): %s %s -> %s",
            duration,
            request.method,
            request.url.path,
            output_path,
        )
    except Exception as exc:
        logger.exception("Failed to write slow request profile: %s", exc)


class PyInstrumentProfilerMiddleware(BaseHTTPMiddleware):
    """Slow-request trap: profile every request; persist HTML when duration >= threshold.

    Profiles are written to BACKEND_ROOT/profiles/, e.g.:
        backend/profiles/20260515_143022_GET_family_group_3.5s.html

    .env:
        SLOW_REQUEST_THRESHOLD=2.0
    """

    async def dispatch(self, request: Request, call_next):
        profiler = Profiler(async_mode="enabled")
        profiler.start()
        started = perf_counter()
        try:
            return await call_next(request)
        finally:
            duration = perf_counter() - started
            profiler.stop()
            if duration >= settings.slow_request_threshold:
                _write_slow_request_profile(profiler, request, duration)


def _run_missed_medications_job() -> None:
    db = SessionLocal()
    try:
        check_missed_medications(db)
    finally:
        db.close()


def _run_weekly_digest_job() -> None:
    db = SessionLocal()
    try:
        send_weekly_digests(db)
    finally:
        db.close()


def _raise_anyio_thread_pool_limit(tokens: int = 200) -> None:
    """Raise Starlette sync-route thread pool (default 40) to reduce anyio.to_thread queueing.

    Related N+1 / lazy-load fixes (see module header comments in each router):
    - vitals.py: GET /vitals/bp|bs — noload(record.user), explicit Pydantic DTOs
    - medications.py: GET /medications/today — batch MedicationLog; plan routes noload user/logs
    - reports.py: GET /reports/clinical-summary — column select for patient; noload on vitals rows
    """
    try:
        limiter = anyio.to_thread.current_default_thread_limiter()
        limiter.total_tokens = tokens
        logger.info("AnyIO default thread pool limit set to %s", limiter.total_tokens)
    except Exception as exc:
        logger.warning("Failed to raise AnyIO thread pool limit: %s", exc)


@asynccontextmanager
async def lifespan(_: FastAPI):
    _raise_anyio_thread_pool_limit(200)
    PROFILES_DIR.mkdir(parents=True, exist_ok=True)
    Base.metadata.create_all(bind=engine)
    scheduler.add_job(
        _run_missed_medications_job,
        "interval",
        hours=1,
        id="missed-medications",
        replace_existing=True,
    )
    scheduler.add_job(
        _run_weekly_digest_job,
        "cron",
        day_of_week="sun",
        hour=20,
        minute=0,
        id="weekly-digests",
        replace_existing=True,
    )
    scheduler.start()
    yield
    if scheduler.running:
        scheduler.shutdown(wait=False)


app = FastAPI(title="Zellia API", lifespan=lifespan)

app.add_middleware(PyInstrumentProfilerMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(medications.router)
app.include_router(vitals.router)
app.include_router(family.router)
app.include_router(pro_share.router)
app.include_router(reports.router)
app.include_router(notifications.router)
app.include_router(webhooks.router)


@app.get("/health")
def health():
    db_ok = False
    cache_ok = False

    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        db_ok = True
    except Exception:
        db_ok = False

    try:
        cache_ok = bool(Redis.from_url(settings.redis_url, socket_connect_timeout=2).ping())
    except Exception:
        cache_ok = False

    status = "ok" if db_ok and cache_ok else "degraded"
    return {
        "status": status,
        "db_backend": "postgres" if "postgresql" in settings.database_url else "sqlite",
        "cache_backend": "redis",
        "db_ok": db_ok,
        "cache_ok": cache_ok,
    }

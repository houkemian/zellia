from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from apscheduler.schedulers.background import BackgroundScheduler
from redis import Redis
from sqlalchemy import text

from app.config import settings
from app.database import Base, SessionLocal, engine
from app.routers import auth, family, medications, notifications, reports, vitals
from app.services.notification_service import check_missed_medications
from app.services.weekly_digest_service import send_weekly_digests

scheduler = BackgroundScheduler()


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


@asynccontextmanager
async def lifespan(_: FastAPI):
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
app.include_router(reports.router)
app.include_router(notifications.router)


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

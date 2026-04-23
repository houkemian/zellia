from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from redis import Redis
from sqlalchemy import text

from app.config import settings
from app.database import Base, engine
from app.routers import auth, family, medications, reports, vitals


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    yield


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

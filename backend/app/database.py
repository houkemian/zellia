from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from sqlalchemy.pool import NullPool

from app.config import settings

connect_args = {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}

if settings.database_url.startswith("sqlite"):
    engine = create_engine(settings.database_url, connect_args=connect_args)
else:
    # Neon -pooler handles server-side pooling; disable SQLAlchemy QueuePool to avoid
    # exhausting local connections (default pool_size=5, max_overflow=10).
    engine = create_engine(
        settings.database_url,
        connect_args=connect_args,
        poolclass=NullPool,
        pool_pre_ping=True,
    )

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

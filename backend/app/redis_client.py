"""Shared Redis clients backed by connection pools (one pool per URL + options)."""

import asyncio
import logging
from threading import Lock

from redis import Redis
from redis.asyncio import Redis as AsyncRedis

from app.config import settings

logger = logging.getLogger(__name__)

_lock = Lock()
_clients: dict[tuple, Redis] = {}
_async_clients: dict[tuple, AsyncRedis] = {}


def _cache_key(
    redis_url: str,
    decode_responses: bool,
    socket_connect_timeout: int,
    socket_timeout: int,
) -> tuple:
    return (redis_url.strip(), decode_responses, socket_connect_timeout, socket_timeout)


def get_redis(
    *,
    redis_url: str | None = None,
    decode_responses: bool = True,
    socket_connect_timeout: int = 3,
    socket_timeout: int = 3,
) -> Redis:
    """Return a cached Redis client (reuses the underlying connection pool)."""
    url = (redis_url or settings.redis_url).strip()
    key = _cache_key(url, decode_responses, socket_connect_timeout, socket_timeout)
    with _lock:
        cached = _clients.get(key)
        if cached is not None:
            return cached
        kwargs = {
            "decode_responses": decode_responses,
            "socket_connect_timeout": socket_connect_timeout,
            "socket_timeout": socket_timeout,
        }
        if url.startswith("rediss://"):
            client = Redis.from_url(url, ssl_cert_reqs=None, **kwargs)
        else:
            client = Redis.from_url(url, **kwargs)
        _clients[key] = client
        return client


def get_async_redis(
    *,
    redis_url: str | None = None,
    decode_responses: bool = True,
    socket_connect_timeout: int = 3,
    socket_timeout: int = 3,
) -> AsyncRedis:
    """Return a cached async Redis client (``redis.asyncio``)."""
    url = (redis_url or settings.redis_url).strip()
    key = _cache_key(url, decode_responses, socket_connect_timeout, socket_timeout)
    with _lock:
        cached = _async_clients.get(key)
        if cached is not None:
            return cached
        kwargs = {
            "decode_responses": decode_responses,
            "socket_connect_timeout": socket_connect_timeout,
            "socket_timeout": socket_timeout,
        }
        if url.startswith("rediss://"):
            client = AsyncRedis.from_url(url, ssl_cert_reqs=None, **kwargs)
        else:
            client = AsyncRedis.from_url(url, **kwargs)
        _async_clients[key] = client
        return client


def ping_redis() -> bool:
    try:
        return bool(
            get_redis(socket_connect_timeout=2, socket_timeout=2).ping()
        )
    except Exception:
        return False


def close_redis_clients() -> None:
    with _lock:
        for client in _clients.values():
            try:
                client.close()
            except Exception as exc:
                logger.debug("redis client close: %s", exc)
        _clients.clear()
        for client in list(_async_clients.values()):
            try:
                asyncio.run(client.aclose())
            except Exception as exc:
                logger.debug("async redis client close: %s", exc)
        _async_clients.clear()

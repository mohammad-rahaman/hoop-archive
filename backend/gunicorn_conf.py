"""Gunicorn configuration for the Hoop Archive API.

Runs FastAPI under multiple worker processes, each an async uvicorn worker, so
requests use all CPU cores instead of a single process. Start with:

    cd backend && gunicorn app.main:app -c gunicorn_conf.py

Worker count is derived from a *database connection budget* rather than cores
alone, because every worker opens its own SQLAlchemy pool. Total connections to
Postgres is:

    workers * (db_pool_size + db_max_overflow)

and must stay under the server's max_connections (default 100). The default
budget below leaves headroom for migrations, psql, and admin connections.

Override any value with an environment variable (WEB_CONCURRENCY, GUNICORN_BIND,
DB_CONNECTION_BUDGET, ...).
"""
import multiprocessing
import os

from app.core.config import settings


def _int_env(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, default))
    except (TypeError, ValueError):
        return default


# Connections one worker may open at peak (full pool + overflow).
_per_worker_conns = max(1, settings.db_pool_size + settings.db_max_overflow)

# Total DB connections we allow the web tier to use. Keep it under Postgres
# max_connections with room for other clients.
_db_budget = _int_env("DB_CONNECTION_BUDGET", 80)

# Cap by the DB budget; otherwise scale with cores. Always keep at least 2.
_budget_workers = max(1, _db_budget // _per_worker_conns)
_cpu_workers = multiprocessing.cpu_count()
_default_workers = max(2, min(_cpu_workers, _budget_workers))

workers = _int_env("WEB_CONCURRENCY", _default_workers)
worker_class = "uvicorn.workers.UvicornWorker"

bind = os.getenv("GUNICORN_BIND", "127.0.0.1:8000")

# Recycle workers periodically to bound any slow leak; jitter avoids a stampede.
max_requests = _int_env("GUNICORN_MAX_REQUESTS", 10000)
max_requests_jitter = _int_env("GUNICORN_MAX_REQUESTS_JITTER", 1000)

# A request that exceeds this (seconds) has its worker killed and replaced, so a
# hung handler can't take the process down permanently.
timeout = _int_env("GUNICORN_TIMEOUT", 30)
graceful_timeout = _int_env("GUNICORN_GRACEFUL_TIMEOUT", 30)
keepalive = _int_env("GUNICORN_KEEPALIVE", 5)

accesslog = os.getenv("GUNICORN_ACCESS_LOG", "-") or None
errorlog = "-"
loglevel = os.getenv("GUNICORN_LOG_LEVEL", "info")


def on_starting(server):
    server.log.info(
        "Hoop Archive: %d workers x %d DB conns = %d max connections "
        "(budget %d, %d cores)",
        workers,
        _per_worker_conns,
        workers * _per_worker_conns,
        _db_budget,
        _cpu_workers,
    )


def post_fork(server, worker):
    """Designate exactly one worker to run the background sync scheduler.

    ``server.worker_age`` increments for each worker the arbiter spawns (the
    first is 1). We set ENABLE_SCHEDULER in that one worker's environment and
    disable it in the rest, so the periodic Sportradar sync runs once, not once
    per worker. This runs before the app is imported in the worker, so Settings
    picks the value up.
    """
    runs_scheduler = server.worker_age == 1
    os.environ["ENABLE_SCHEDULER"] = "1" if runs_scheduler else "0"
    if runs_scheduler:
        worker.log.info("Worker %s owns the background sync scheduler", worker.pid)

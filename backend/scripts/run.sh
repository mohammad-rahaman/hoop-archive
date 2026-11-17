#!/usr/bin/env bash
# Start the Hoop Archive API under Gunicorn with multiple uvicorn workers.
#
#   ./scripts/run.sh            # production-style multi-worker server
#   WEB_CONCURRENCY=4 ./scripts/run.sh   # pin the worker count
#
# For local development with autoreload, prefer a single uvicorn worker instead:
#   uvicorn app.main:app --reload
set -euo pipefail

cd "$(dirname "$0")/.."
export PYTHONPATH="${PYTHONPATH:-.}"

exec gunicorn app.main:app -c gunicorn_conf.py "$@"

# 🏀 Hoop Archive

A mobile-first NBA player analytics app. Browse and search players, explore
season-by-season statistics and trend charts, and compare two players
side-by-side — across historical seasons from **1979** to today, with offline
access to anything you've already viewed.

> Portfolio project demonstrating Flutter, FastAPI, PostgreSQL, data
> engineering (ETL), third-party API integration, data visualization, and
> offline-first architecture.

---

## Features

- **Browse & search** players with debounced search and team / position
  filters, infinite-scroll pagination.
- **Player profiles** with full season-by-season stat tables, a regular-season
  / playoffs toggle, and multi-team seasons shown alongside the league `TOT`
  aggregate.
- **Trend charts** (`fl_chart`) of scoring and efficiency across a career, with
  missing seasons skipped rather than drawn as zero.
- **Side-by-side comparison** of two players on career averages, with per-metric
  leader highlighting and an honest "not comparable" state for metrics one
  player is missing (never scored as 0).
- **Current-season sync** from Sportradar through a swappable provider, behind a
  dependency-free scheduled background job that is **off unless configured**.
- **Offline access** — every response you load is cached locally, so players,
  profiles, comparisons and the overview replay from disk when the network is
  unavailable, with an offline banner and a "saved copy" freshness note.

---

## Architecture

```
Hoop Archive/
├── backend/                 FastAPI + PostgreSQL + Alembic
│   ├── app/
│   │   ├── core/            config (env-driven; API keys stay server-side)
│   │   ├── db/              SQLAlchemy 2.0 models, engine/session
│   │   ├── api/routes/      HTTP endpoints (health, players, sync)
│   │   ├── schemas/         Pydantic v2 request/response models
│   │   ├── services/        player queries, career aggregation, comparison,
│   │   │   │                sync + scheduler
│   │   │   └── providers/   StatsProvider interface
│   │   ├── providers/       Sportradar client (key read server-side only)
│   │   └── etl/             CSV inspection, validation & idempotent ingestion
│   ├── alembic/             migrations
│   ├── data/sample/         synthetic sample CSV + sample Sportradar JSON
│   └── tests/               pytest (ETL, comparison, APIs, sync, scheduler)
└── mobile/                  Flutter app
    └── lib/
        ├── core/
        │   ├── api/         Dio client (cache-aware) + DTOs
        │   ├── cache/       KeyValueStore + ResponseCache (offline)
        │   ├── widgets/     shared UI (offline banner)
        │   └── …            env, theme, router, connectivity
        └── features/        home, players (list/profile/trends), compare
```

**Data flow:** Kaggle historical CSV → ETL (validate + idempotent upsert) →
PostgreSQL → FastAPI → Flutter. The Flutter client caches every response in a
local document cache (write-through on success, read-through on failure) for
offline access. Current/recent data is fetched **server-side** from Sportradar
through a swappable `StatsProvider` abstraction and merged into the same tables.

### Data model
`Player` · `Team` · `Season` · `PlayerSeasonStats` · `SyncMetadata`

- Player identity uses a normalized `name_key`, **not** the raw name, so
  re-ingestion updates rows instead of duplicating them.
- A season can span multiple teams — each `(player, season, team, season_type)`
  is its own stat row, so multi-team seasons and the league `TOT` aggregate all
  coexist.
- Regular season and playoffs are kept **distinct** (`season_type`).
- Missing statistics are stored as `NULL`, **never 0**.

### Offline cache (mobile)
The client uses a document cache (keyed JSON responses) rather than a relational
store, because the access pattern is "replay the last response for this
request", not relational querying. It lives behind a `KeyValueStore` interface
(`SharedPreferences` in the app, in-memory in tests), so a heavier engine
(e.g. Drift/SQLite) can be dropped in later without touching call sites. Entries
never hard-expire — stale data is still shown offline — but are labelled by age
and bounded with oldest-first eviction.

---

## Backend — setup & run

Requirements: Python 3.9+, PostgreSQL 14+.

```bash
cd backend
python3 -m pip install -r requirements.txt
cp .env.example .env          # adjust DATABASE_URL / Sportradar key if needed
createdb hoop_archive         # one-time
export PYTHONPATH=.
python3 -m alembic upgrade head
uvicorn app.main:app --reload # http://localhost:8000  (/docs for OpenAPI)
```

### Ingesting data

```bash
# Inspect a dataset without writing anything (audit report):
python3 -m app.etl.ingest --csv ../cleaned_data.csv --year-is-end --audit-only

# Idempotent ingestion (safe to re-run; updates instead of duplicating):
python3 -m app.etl.ingest --csv ../cleaned_data.csv --year-is-end

# Replace all existing data (e.g. removing prior sample data) with the CSV:
python3 -m app.etl.ingest --csv ../cleaned_data.csv --year-is-end --replace
```

The ingester maps CSV headers flexibly (case/punctuation-insensitive aliases),
reports unmapped/missing columns, and refuses to run if required fields
(`player_name`, `season`) are absent.

### Current-season sync (Sportradar)

Sync is **disabled by default** and makes no external calls until fully
configured. Set the following in `.env` to enable it:

```bash
SPORTRADAR_API_KEY=...        # read server-side only; never sent to the client
SYNC_ENABLED=true
SYNC_SEASON_YEAR=2024
SYNC_TEAM_IDS=sr:team:...     # comma-separated
SYNC_INTERVAL_HOURS=24
SYNC_ADMIN_TOKEN=...          # guards the manual trigger endpoint
```

With those set, a background scheduler refreshes the configured teams on an
interval. A manual run is available at `POST /sync/sportradar` (requires the
`X-Sync-Token` header when `SYNC_ADMIN_TOKEN` is set). When unconfigured, a sync
records a `skipped` run and the app keeps serving historical data.

### API endpoints
| Method | Path | Description |
|--------|------|-------------|
| GET  | `/health` | Liveness check |
| GET  | `/meta` | Row counts, season range, last sync, Sportradar status |
| GET  | `/players` | List / search / filter players (`q`, `team`, `position`, `season`; paginated) |
| GET  | `/players/filters` | Available team, position & season filter values |
| GET  | `/players/compare` | Compare two players (`a`, `b`, `season_type`); add `a_season` / `b_season` (e.g. `2015-16`) to compare single seasons instead of careers |
| GET  | `/players/{id}` | Player profile + season statistics |
| GET  | `/sync/status` | Sync configuration & recent runs (no key leaked) |
| POST | `/sync/sportradar` | Trigger a Sportradar sync (token-guarded) |

### Tests
```bash
cd backend && PYTHONPATH=. python3 -m pytest -q   # 71 tests
```
Tests run on in-memory SQLite — no running Postgres required, and no external
network calls (the Sportradar client is exercised with a mock transport).

### Running at scale (production)

`uvicorn --reload` is a single process — fine for development, but it serves
requests from one CPU core. For production, run under **Gunicorn with uvicorn
workers** so requests use every core:

```bash
cd backend && ./scripts/run.sh            # gunicorn -c gunicorn_conf.py
WEB_CONCURRENCY=4 ./scripts/run.sh        # pin the worker count
```

Each worker opens its own SQLAlchemy pool, so the total connections to Postgres
is `workers × (db_pool_size + db_max_overflow)` and must stay under the server's
`max_connections` (default 100). `gunicorn_conf.py` derives the worker count
from a connection *budget* (`DB_CONNECTION_BUDGET`, default 80) for exactly this
reason, and logs the resulting `workers × conns = total` on startup.

Key tuning knobs (env / `.env`):

| Setting | Default | Purpose |
|---------|---------|---------|
| `DB_POOL_SIZE` | 10 | Persistent connections per worker |
| `DB_MAX_OVERFLOW` | 5 | Extra burst connections per worker |
| `DB_POOL_TIMEOUT` | 10s | **Fail fast** when no connection is free, instead of hanging |
| `DB_STATEMENT_TIMEOUT_MS` | 15000 | Cancel a runaway query and return its connection |
| `WEB_CONCURRENCY` | auto | Gunicorn worker count (else derived from the budget) |
| `DB_CONNECTION_BUDGET` | 80 | Upper bound on total DB connections across workers |

Under a multi-worker server the background sync scheduler runs in **one** worker
only (`gunicorn_conf.py` assigns it via `post_fork`), so a configured Sportradar
sync doesn't fan out to every process.

### Load testing

A repeatable load harness lives in [`backend/loadtest/`](backend/loadtest/). It
hits the API with a realistic read-only endpoint mix:

```bash
cd backend
python3 loadtest/ramp.py                               # open-model arrival ramp
STAGES="25:10,250:10,1000:10" python3 loadtest/ramp.py # custom ramp
```

It reports per-stage success % and p50/p95/p99 latency and flags the capacity
*knee*. CI runs a gentle version of it as a gate (see
[`.github/workflows/ci.yml`](.github/workflows/ci.yml)), seeding **synthetic**
data (`loadtest/seed_demo.py`, not real NBA data) so it needs no licensed
dataset.

**Measured on a 10-core dev machine:** steady-state the API serves ~500 req/s at
~5 ms p95. The `pool_timeout` guard means a sudden flood of simultaneous
connections now degrades and **self-recovers** in seconds (fast-failing the
backlog) rather than wedging the process permanently as before. Staying fully
*responsive* during such a flood — rejecting excess with a quick `503` — is the
next step (an application-level concurrency limit / load-shedder), along with
response caching (`Cache-Control`/ETag; the data is largely static) and a
reverse-proxy micro-cache.

---

## Mobile — setup & run

Requirements: Flutter 3.24+.

```bash
cd mobile
flutter pub get
flutter run                                                   # iOS sim / localhost
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   # Android emulator
```
The Android emulator reaches the host machine via `10.0.2.2`; the iOS simulator
uses `localhost`. Override with `--dart-define=API_BASE_URL=...` for a physical
device on your LAN.

```bash
flutter test       # 39 tests
flutter analyze    # no issues
```

See [`mobile/README.md`](mobile/README.md) for the app's internal structure.

---

## Data provenance & licensing

- The historical dataset is a **Kaggle NBA CSV** provided locally for
  development. Its license is **not assumed** to permit public redistribution,
  so no real Kaggle data is committed to this repository. Place your CSV under
  `backend/data/` (git-ignored) and point the ingester at it.
- `backend/data/sample/sample_nba_synthetic.csv` and
  `sportradar_seasonal_statistics_sample.json` are **synthetic, fabricated
  data** created solely to exercise the pipeline and tests — the players are not
  real.
- **Sportradar** trial data is for internal evaluation only and is not
  redistributed. The API key is read only on the backend (`SPORTRADAR_API_KEY`)
  and is never exposed to the Flutter client.

---

## Roadmap (MVP phases)

| Phase | Scope | Status |
|------:|-------|--------|
| 1 | Repo audit + architecture scaffold (both tiers) | ✅ Done |
| 2 | PostgreSQL schema, migrations, idempotent CSV ingestion | ✅ Done |
| 3 | Player list, search, team/position filters, pagination | ✅ Done |
| 4 | Player profile & season statistics | ✅ Done |
| 5 | Trend charts (fl_chart) | ✅ Done |
| 6 | Player comparison (leader highlighting) | ✅ Done |
| 7 | Sportradar integration & scheduled sync | ✅ Done |
| 8 | Offline caching (document cache, swappable store) | ✅ Done |
| 9 | Testing, UI polish, docs | ✅ Done |

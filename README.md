# 🏀 Hoop Archive

A mobile-first NBA player analytics app. Browse and search players, explore
season-by-season statistics and trend charts, and compare two players
side-by-side — across historical seasons from **1980** to today, with offline
access to anything you've already viewed.

> Portfolio project demonstrating Flutter, FastAPI, PostgreSQL, data
> engineering (ETL), API integration, data visualization, and offline-first
> architecture.

---

## Architecture

```
Hoop Archive/
├── backend/                 FastAPI + PostgreSQL + Alembic
│   ├── app/
│   │   ├── core/            config (env-driven; API keys stay server-side)
│   │   ├── db/              SQLAlchemy models, engine/session
│   │   ├── api/routes/      HTTP endpoints
│   │   ├── services/        comparison logic, provider abstraction
│   │   │   └── providers/   StatsProvider interface (Sportradar impl → Phase 7)
│   │   └── etl/             CSV inspection, validation & idempotent ingestion
│   ├── alembic/             migrations
│   ├── data/sample/         synthetic sample CSV (NOT real Kaggle data)
│   └── tests/               pytest (ETL, validation, comparison)
└── mobile/                  Flutter app
    └── lib/
        ├── core/            env, theme, router, Dio API client, DTOs
        └── features/        feature screens (home/overview today)
```

**Data flow:** Kaggle historical CSV → ETL (validate + idempotent upsert) →
PostgreSQL → FastAPI → Flutter (with a local SQLite/Drift cache for offline,
added in Phase 8). Current/recent data is fetched server-side from Sportradar
through a swappable `StatsProvider` abstraction.

### Data model
`Player` · `Team` · `Season` · `PlayerSeasonStats` · `SyncMetadata`

- Player identity uses a normalized `name_key`, **not** the raw name, so
  re-ingestion updates rows instead of duplicating them.
- A season can span multiple teams — each `(player, season, team, season_type)`
  is its own stat row, so multi-team seasons and the league `TOT` aggregate all
  coexist.
- Regular season and playoffs are kept **distinct** (`season_type`).
- Missing statistics are stored as `NULL`, **never 0**.

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
python3 -m app.etl.ingest --csv data/sample/sample_nba_synthetic.csv --audit-only

# Idempotent ingestion (safe to re-run; updates instead of duplicating):
python3 -m app.etl.ingest --csv data/sample/sample_nba_synthetic.csv
```

The ingester maps CSV headers flexibly (case/punctuation-insensitive aliases),
reports unmapped/missing columns, and refuses to run if required fields
(`player_name`, `season`) are absent.

### API endpoints (current)
| Method | Path      | Description |
|--------|-----------|-------------|
| GET    | `/health` | Liveness check |
| GET    | `/meta`   | Row counts, season range, last sync, Sportradar status |

More endpoints (player list/search/filter, profile, comparison) arrive in
Phases 3–6.

### Tests
```bash
cd backend && PYTHONPATH=. python3 -m pytest -q
```
Tests run on in-memory SQLite — no running Postgres required.

---

## Mobile — setup & run

Requirements: Flutter 3.24+.

```bash
cd mobile
flutter pub get
flutter run                                   # iOS simulator / localhost
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   # Android emulator
```
The Android emulator reaches the host machine via `10.0.2.2`; the iOS simulator
uses `localhost`. Override with `--dart-define=API_BASE_URL=...` for a physical
device on your LAN.

---

## Data provenance & licensing

- The historical dataset is a **Kaggle NBA CSV** provided locally for
  development. Its license is **not assumed** to permit public redistribution,
  so no real Kaggle data is committed to this repository. Place your CSV under
  `backend/data/` (git-ignored) and point the ingester at it.
- `backend/data/sample/sample_nba_synthetic.csv` is **synthetic, fabricated
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
| 3 | Player list, search, team/position filters, pagination | ⏭ Next |
| 4 | Player profile & season statistics | — |
| 5 | Trend charts (fl_chart) | — |
| 6 | Player comparison (leader highlighting) | — |
| 7 | Sportradar integration & scheduled sync | — |
| 8 | Offline caching (Drift/SQLite) | — |
| 9 | Testing, UI polish, docs | — |

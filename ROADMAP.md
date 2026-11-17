# Roadmap

Hoop Archive is a complete MVP: browse, profile, and compare players (careers
or single seasons) across the 1979–2020-21 archive, backed by a tested FastAPI
service and a Flutter app. The items below are deliberate next steps, not gaps
in the shipped product.

## Backend / infrastructure

- **Load-shedding under extreme bursts.** The API already runs multi-worker
  (Gunicorn + uvicorn) with a tuned, fail-fast connection pool, so a sudden
  flood degrades and self-recovers instead of wedging. Staying fully
  *responsive* during such a burst — returning a quick `503` rather than
  briefly going dark — needs an application-level concurrency limit /
  load-shedder. Response caching (`Cache-Control`/ETag; the data is largely
  static) is the natural follow-on. See `backend/loadtest/` for the harness
  that measures this.
- **CI green check.** `.github/workflows/ci.yml` runs the unit tests and a
  Postgres-backed load smoke gate, startable from the Actions tab
  (`workflow_dispatch`). It is in place and valid; the first run is pending a
  GitHub account billing matter, unrelated to the code.

## Data

- **Live current-season sync.** The Sportradar sync path exists and is wired
  up but ships **off** (no API key committed, by design). The archive covers
  1979–2020-21; adding a key on the backend enables current-season refresh
  without any client change. The key never reaches the Flutter app.

## Nice-to-haves

- Per-metric sort on the players list (e.g. top scorers of a season).
- Multi-season trend overlay in Compare (two players' full career lines on one
  chart, not just one season each).
- iPad layout (the app is iPhone-first today).

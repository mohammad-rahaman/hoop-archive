# Load testing

Repeatable capacity tests for the Hoop Archive API. They hit the **backend** —
the resource shared by all concurrent app users — with a realistic read-only
endpoint mix (list, profile, meta, filters, compare). No data is written.

## `ramp.py` — open-model ramp (primary)

Fires requests at a target **arrival rate** that steps up through stages,
without waiting for responses. This is the realistic model (users arrive on
their own schedule) and exposes the capacity *knee* — the stage where p95
latency climbs and success drops.

```bash
cd backend
python3 loadtest/ramp.py
```

Tune the ramp and target:

```bash
STAGES="25:10,100:10,250:10,500:10,1000:10" python3 loadtest/ramp.py
BASE=http://127.0.0.1:8001 python3 loadtest/ramp.py
```

Each stage prints offered vs sent vs shed requests, success %, and p50/p95/p99
latency, then the knee is flagged at the end.

## Before/after a change

1. Start the single-worker baseline and run the ramp:
   ```bash
   uvicorn app.main:app --port 8000
   BASE=http://127.0.0.1:8000 python3 loadtest/ramp.py
   ```
2. Start the multi-worker server and run the same ramp:
   ```bash
   ./scripts/run.sh                 # gunicorn, multiple uvicorn workers
   python3 loadtest/ramp.py
   ```
3. Compare the knee and the p95 at each stage.

## Interpreting results

- **shed > 0** means the *client* hit its in-flight cap, not the server — raise
  `MAX_INFLIGHT` or lower the rate; those requests never reached the backend.
- A healthy backend holds p95 roughly flat as rps rises, then degrades at the
  knee. Under overload a well-behaved server returns errors/timeouts quickly
  (load-shedding) rather than latency climbing without bound.
- 1,000 concurrent *users* is not 1,000 requests/second: users read and think
  between taps, and the app's offline cache suppresses repeat calls. Use the
  knee (req/s) with an estimate of requests-per-user-per-minute to reason about
  supported concurrent users.

> Run load tests only against a local or dedicated test instance, never a shared
> production database.

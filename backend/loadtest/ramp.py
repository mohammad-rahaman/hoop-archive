"""Open-model ramp load test for the Hoop Archive API.

Unlike a closed-loop test (N workers that each wait for a response before
sending the next request), this fires requests at a *target arrival rate* that
steps up through stages, regardless of how fast the server replies. That models
real traffic — users arrive on their own schedule — and makes the capacity
"knee" visible: the stage where p95 latency climbs and success drops is the
point the backend can no longer keep up.

Usage:
    cd backend
    python3 loadtest/ramp.py
    STAGES="25:10,100:10,250:10,500:10,1000:10" python3 loadtest/ramp.py
    BASE=http://127.0.0.1:8001 python3 loadtest/ramp.py

Env vars:
    BASE          base URL (default http://127.0.0.1:8000)
    STAGES        comma-separated "rps:seconds" stages
                  (default "25:8,75:8,150:8,300:8,600:8")
    RTO           per-request read timeout seconds (default 10)
    MAX_INFLIGHT  safety cap on concurrent in-flight requests (default 3000);
                  requests that would exceed it are counted as "shed" (the
                  client could not offer the load) rather than sent.

This measures the backend (the shared resource for N concurrent app users), not
the Flutter client. It only issues read-only GETs.
"""
import asyncio
import os
import random
import sys
import time
from collections import Counter

import httpx

BASE = os.getenv("BASE", "http://127.0.0.1:8000")
RTO = float(os.getenv("RTO", "10"))
MAX_INFLIGHT = int(os.getenv("MAX_INFLIGHT", "3000"))
STAGES_SPEC = os.getenv("STAGES", "25:8,75:8,150:8,300:8,600:8")

# CI gate (optional): when set, fail the process if any stage that actually sent
# requests breaches these thresholds. Use a gentle STAGES in CI so the gate
# asserts healthy behaviour rather than the overload region.
ASSERT_OK_PCT = float(os.environ["ASSERT_OK_PCT"]) if os.getenv("ASSERT_OK_PCT") else None
ASSERT_P95_MS = float(os.environ["ASSERT_P95_MS"]) if os.getenv("ASSERT_P95_MS") else None


def parse_stages(spec: str):
    stages = []
    for part in spec.split(","):
        rps_s, dur_s = part.split(":")
        stages.append((float(rps_s), float(dur_s)))
    return stages


def build_mix(ids):
    def rnd_id():
        return random.choice(ids)

    def cmp():
        a = random.choice(ids)
        b = random.choice([i for i in ids if i != a] or [a])
        return f"/players/compare?a={a}&b={b}&season_type=regular"

    mix = []
    mix += ["/players?page=1&page_size=25"] * 40
    mix += [lambda: f"/players/{rnd_id()}"] * 25
    mix += ["/meta"] * 15
    mix += ["/players/filters"] * 10
    mix += [cmp] * 10
    return mix


def pct(sorted_vals, p):
    if not sorted_vals:
        return 0.0
    k = min(len(sorted_vals) - 1, int(round((p / 100.0) * (len(sorted_vals) - 1))))
    return sorted_vals[k]


class Inflight:
    """Single-threaded in-flight counter with a hard cap (no lock needed under
    asyncio). ``try_enter`` is non-blocking so we never pace the load generator
    to the server's speed — that's what keeps this an *open* model."""

    def __init__(self, cap):
        self.cap = cap
        self.count = 0

    def try_enter(self) -> bool:
        if self.count >= self.cap:
            return False
        self.count += 1
        return True

    def leave(self):
        self.count -= 1


class Stage:
    def __init__(self, rps, dur):
        self.rps = rps
        self.dur = dur
        self.offered = 0        # requests the schedule wanted to send
        self.sent = 0           # actually dispatched
        self.shed = 0           # not sent (in-flight cap hit)
        self.lat = []           # completed latencies (ms)
        self.status = Counter()
        self.errors = Counter()

    def done(self, dt_ms, code=None, err=None):
        self.lat.append(dt_ms)
        if code is not None:
            self.status[code] += 1
        if err is not None:
            self.errors[err] += 1

    def report(self):
        lat = sorted(self.lat)
        completed = len(lat)
        ok = sum(v for k, v in self.status.items() if 200 <= k < 400)
        ok_pct = (100.0 * ok / completed) if completed else 0.0
        return {
            "target_rps": self.rps,
            "offered": self.offered,
            "sent": self.sent,
            "shed": self.shed,
            "completed": completed,
            "ok_pct": ok_pct,
            "p50": pct(lat, 50),
            "p95": pct(lat, 95),
            "p99": pct(lat, 99),
            "max": lat[-1] if lat else 0.0,
            "status": dict(self.status),
            "errors": dict(self.errors),
        }


async def fire(client, url, stage, inflight):
    t0 = time.perf_counter()
    try:
        r = await client.get(url)
        stage.done((time.perf_counter() - t0) * 1000.0, code=r.status_code)
    except Exception as e:  # noqa: BLE001
        stage.done((time.perf_counter() - t0) * 1000.0, err=type(e).__name__)
    finally:
        inflight.leave()


async def run_stage(client, mix, stage, inflight, tasks):
    interval = 1.0 / stage.rps if stage.rps > 0 else stage.dur
    start = time.perf_counter()
    deadline = start + stage.dur
    next_at = start
    while True:
        now = time.perf_counter()
        if now >= deadline:
            break
        if now < next_at:
            await asyncio.sleep(min(next_at - now, deadline - now))
            continue
        next_at += interval
        stage.offered += 1
        if not inflight.try_enter():
            stage.shed += 1
            continue
        stage.sent += 1
        target = random.choice(mix)
        url = target() if callable(target) else target
        tasks.append(asyncio.create_task(fire(client, url, stage, inflight)))


async def main():
    stages = [Stage(rps, dur) for rps, dur in parse_stages(STAGES_SPEC)]
    async with httpx.AsyncClient(base_url=BASE, timeout=10) as c:
        resp = await c.get("/players?page=1&page_size=100")
        ids = [p["id"] for p in resp.json()["items"]]
    if not ids:
        raise SystemExit("No players to test against — is the DB seeded?")
    mix = build_mix(ids)

    inflight = Inflight(MAX_INFLIGHT)
    limits = httpx.Limits(max_connections=MAX_INFLIGHT, max_keepalive_connections=512)
    timeout = httpx.Timeout(connect=5.0, read=RTO, write=5.0, pool=RTO)

    print(f"base   : {BASE}")
    print(f"ids    : {len(ids)} players under test")
    print(f"stages : {STAGES_SPEC}")
    print(f"cap    : {MAX_INFLIGHT} in-flight\n")
    header = (
        f"{'target rps':>10} {'offered':>8} {'sent':>7} {'shed':>6} "
        f"{'ok%':>7} {'p50':>7} {'p95':>8} {'p99':>8} {'max':>8}"
    )
    print(header)
    print("-" * len(header))

    async with httpx.AsyncClient(base_url=BASE, limits=limits, timeout=timeout) as client:
        for stage in stages:
            stage_tasks: list = []
            await run_stage(client, mix, stage, inflight, stage_tasks)
            # Let this stage's in-flight requests finish before reporting it.
            if stage_tasks:
                await asyncio.gather(*stage_tasks)
            r = stage.report()
            print(
                f"{r['target_rps']:>10.0f} {r['offered']:>8} {r['sent']:>7} "
                f"{r['shed']:>6} {r['ok_pct']:>6.1f}% {r['p50']:>7.0f} "
                f"{r['p95']:>8.0f} {r['p99']:>8.0f} {r['max']:>8.0f}"
            )

    print("\nlatency in ms. 'shed' = client hit the in-flight cap (not sent).")
    reports = [s.report() for s in stages]
    knee = next(
        (r["target_rps"] for r in reports if r["ok_pct"] < 99.0 or r["p95"] > 1000.0),
        None,
    )
    if knee is not None:
        print(f"knee   : degradation begins around {knee:.0f} req/s")
    else:
        print("knee   : no degradation observed across the tested range")
    for r in reports:
        if r["errors"]:
            print(f"  errors @ {r['target_rps']:.0f} rps: {r['errors']}")

    # Optional CI gate.
    if ASSERT_OK_PCT is not None or ASSERT_P95_MS is not None:
        failures = []
        for r in reports:
            if r["completed"] == 0:
                continue
            if ASSERT_OK_PCT is not None and r["ok_pct"] < ASSERT_OK_PCT:
                failures.append(
                    f"stage {r['target_rps']:.0f} rps: ok {r['ok_pct']:.1f}% "
                    f"< {ASSERT_OK_PCT:.1f}%"
                )
            if ASSERT_P95_MS is not None and r["p95"] > ASSERT_P95_MS:
                failures.append(
                    f"stage {r['target_rps']:.0f} rps: p95 {r['p95']:.0f}ms "
                    f"> {ASSERT_P95_MS:.0f}ms"
                )
        if failures:
            print("\nLOAD GATE FAILED:")
            for f in failures:
                print(f"  - {f}")
            sys.exit(1)
        print("\nLOAD GATE PASSED")


if __name__ == "__main__":
    asyncio.run(main())

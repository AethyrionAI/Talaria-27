# OJAMD Relay Deploy — #37 self-heal (issue #15)

**Context for the session picking this up:** PR #37 (merged to main,
`99848ee`) rewrites `relay/app/*` to self-heal dead relay credentials:
typed refresh outcomes, silent re-registration, refresh-token grace.
The relay RUNNING on OJAMD predates it — Talaria's Talk Engine still
401s at `talk/readiness` until this deploys. Tests: relay 59/59 green.

**Machine:** OJAMD (Windows). NSSM services: `HermesGateway` (:8642),
`HermesMobileRelay` (:8000), `TalariaModelsShim` (:8765). Only the
relay (:8000) is in scope here.

**Known risk (why this runbook exists):** live relay code on OJAMD may
contain changes never committed to git. Deploying blind could clobber
them. Steps 2–3 are mandatory, not optional.

## Procedure

1. **Locate the live install.** Find the relay dir NSSM points at:
   `nssm get HermesMobileRelay AppDirectory` (and `Application` /
   `AppParameters` for how it's launched). Note the Python env it uses.

2. **Back up the DB.** Read `relay/app/config.py` + any `.env` in the
   live dir to find the DB path (SQLite file expected). Stop nothing
   yet — copy the DB file to `<db>.pre37.bak` (plus `-wal`/`-shm`
   siblings if present).

3. **Drift check (mandatory).** Diff live code vs git:
   - If the live dir is a git checkout: `git status` + `git diff` +
     `git log --oneline -3` there.
   - If it's a plain copy: clone/pull ChronoRixun/Talaria fresh and
     diff the trees, e.g.
     `git diff --no-index <live>/app <clone>/relay/app`.
   - **If drift found:** STOP. Reconcile into git first (commit to a
     branch, PR it), then restart this runbook. Do not deploy over it.

4. **Back up live code.** Zip/copy the live relay dir to
   `relay.pre37.bak/` — this is the rollback unit.

5. **Deploy.** `nssm stop HermesMobileRelay` → update code to main
   (`git pull` if checkout; else copy `relay/` from a fresh clone).
   Install/refresh deps in the service's Python env per
   `relay/pyproject.toml`. **Check whether #37 expects any new config
   keys** (`git diff 03f3862..main -- relay/app/config.py`) and add to
   `.env` if so. `nssm start HermesMobileRelay`.

6. **Smoke-test host-side.** Tail the relay log; hit a health/readiness
   endpoint locally. Confirm no schema errors on startup (#37 touches
   `database.py`/`models.py`).

7. **Device test (phone in hand).**
   a. Open Talaria → Voice → Talk Engine. Ideal: self-heal kicks in and
      readiness goes green without a re-pair (that's the whole point
      of #37 — silent re-registration).
   b. If still 401: re-pair the device once, then confirm readiness →
      session → OpenAI SDP exchange end-to-end.
   c. Check sensors ride the same token successfully.
   d. Result closes (or updates) issue #7's e2e acceptance box.

8. **Rollback (if broken):** `nssm stop HermesMobileRelay` → restore
   `relay.pre37.bak/` code + `<db>.pre37.bak` → `nssm start`. Old 401
   behavior returns but service is known-good.

## Post-deploy notes
- Backlog while in there: `connector/tests/test_sensor_store.py` has 5
  read-back failures (health/location queries return empty) — host-side
  sensor store, same machine, worth a look if time permits.
- Gateway (:8642) and shim (:8765) are untouched by this deploy.

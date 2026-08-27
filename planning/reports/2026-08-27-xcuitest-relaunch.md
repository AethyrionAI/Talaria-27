# The `testConnectedRelaunchSkipsTheConnectEntry` intermittent — 10-hour diagnosis, honest verdict

**2026-08-27. The dedicated lane (Owen's go) ran ~04:30–14:12 and was cut
short by a Claude Code process exit; this report is the orchestrator's
harvest of its artifacts. The lane merged nothing; its one durable code
product (the XFLAKE instrumentation) was extracted and committed by the
orchestrator with the evidence below.**

## The verdict: NOT reproducible under synthetic load — the red needs real concurrent gate activity

Seven-plus induced-load reproduction attempts across the day, escalating
to **load average 186**, and the target test **passed every time**:

| run | time | load avg at start→end | target test |
|---|---|---|---|
| loaded-1 | 09:08 | high | PASS |
| loaded-2 | 09:23 | high | PASS |
| loaded-3-full (full bundle) | 09:24–09:47 | 26 → **186** | **PASS, 63.877 s** |
| probe-1..4 (instrumented) | 13:33–13:39 | 13–50 | PASS ×4, 38.9–48.3 s |

The slowest observation is a **64-second PASS** — the 15 s
post-tap `waitForComposer` budget was never the binding constraint under
pure CPU/load pressure. Every historical RED (4-ish across ~10 full-suite
runs on unchanged trees, 08-26/27) occurred during **real concurrent lane
activity**: a second `lane-gate.sh` mid-Release, sim boots, mutation
churn. Whatever the mechanism is, synthetic load does not summon it;
something about genuine parallel xcodebuild/simulator work does.
Candidates that survive (untested): CoreSimulator service contention,
DerivedData/db pressure, runner-side springboard stalls (#219's family).
Candidates killed: plain CPU/memory load; the app being slow to land in
chat (it lands — slowly — and passes).

## The tripwire (committed to main)

Two `XCTContext.runActivity` diagnostic lines now bracket the START
CHATTING tap inside the test (`XFLAKE pre/post`: hittability, frames,
wizard state, a 5 s composer pre-check). **The next NATURAL red
self-documents in its own `.xcresult`** — no reproduction hunt needed;
diagnosis resumes from that artifact. Verification for the
instrumentation itself: the instrumented test passed **7 consecutive
loaded runs** (the table above) — stronger evidence than one more quiet
gate.

## Artifacts

`~/.talaria-instrument-runs/20260827-xflake-diagnosis/xflake-logs/` —
all seven `.xcresult`s (incl. the 110 MB full-bundle run), runner logs,
load logs, `probe-all.json` aggregation. **#219 finally has its owed
`.xcresult`s** — of passing runs, which still bound the timing envelope.

## Disposition

**WATCH, tripwire armed.** No assertion was relaxed, no budget widened
on a shrug — the brief forbade fixing without a mechanism and the
mechanism declined to appear under observation. The next gate red on
this test carries its own diagnosis; that is the moment to act.

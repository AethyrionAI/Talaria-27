# SDD ledger — plan: planning/superpowers/plans/2026-08-12-unattended-instrument-runner.md

Worktree: .claude/worktrees/lane-333 (branch t27-333-instrument-runner off 5b1ba58)
Parallel context: #332-a/b lane runs concurrently in its own worktree (disjoint files except OPEN_ITEMS.md).
Device tasks (9, 10) are controller-owned; implementer subagents never touch physical devices.
Task 1: minor (deferred): result filename lacks run-unique id (same-second collision); latest/result pair not cross-atomic (brief-mandated design); instrument name not filesystem-sanitized in filename
Task 1: complete (commits 5b1ba58..50bd98c, review clean)
Task 2: complete (commits 50bd98c..c079544, review clean)
Task 3: complete (commits c079544..7a53ac7, review clean; brief's sample corrected by reality: cells is [ActionBatteryCell] and unused by buttons, run's backend param is Optional)
Task 4: fix round 1/5 (1 open — false completed on battery-mutex refusal; fix: completed requires new run record, injectable loadRuns seam; commits pending)
Task 4: fix round 1/5 (1 addressed, 0 open; commits fe8fce5..c5d8e8b)
Task 4: minor (deferred): completion heuristic can't name WHICH cause blocked a record (reason string names both); alarmWritesAttended static cross-test bleed inherited from #331
Task 4: complete (commits 7a53ac7..c5d8e8b, review clean after 1 fix round)
Task 5: complete (commits c5d8e8b..5a691c0, review clean; sim smoke: latest.json completed for router-probe via SIMCTL_CHILD env)
Task 6: minor (deferred): restore "post-denial recovery" rationale on shape entry (overwritten, gone from tree); restore idle-timer why-comment near InstrumentConductor isIdleTimerDisabled; reconsider nonAcceptInstrumentsWriteNothing test (pressures flags in the unsafe direction for future unclear entries)
Task 6: controller rulings: cells plumbing stays inert-but-reserved (document at #333 close-out); attended iPad refusal for write instruments is INTENDED (Owen's device-based rule, not attendance-based)
Task 6: complete (commits 5a691c0..5a71d9d, review clean; 45 entries, screen 2280->1056 lines, gate PASS incl. Release run by implementer)
Order deviation: Task 8 dispatched before Task 7's formal gate — the gate will run once on the final tree (script-only Task 8 can't affect the suite, but the gate certifies the tree it ran on).
Task 7: complete (gate on final tree @ 9cc9285: GATE: PASS, 2167 Swift Testing + 14 XCUITest + Release; log at .superpowers/sdd/2026-08-12-unattended-instrument-runner/gate-final.log) — NOTE gate must re-run if Task 8 fix lands after (script-only; suite unaffected; pbxproj drift check is what matters)
Task 8: fix round 1/5 (5 open — Critical stale-guard arms on previous run's artifact; missing-value args exit 1 not 3; unhung copy timeout; SECONDS wall-clock; TIMEOUT leaves device app hung)
Task 8: fix round 1/5 (6 addressed, 2 new/residual open — unbounded terminate call; baseline-fetch-failure stale window; commits 9cc9285..c685aad)
Task 8: fix round 2/5 dispatched (bound every devicectl call; three-state baseline: present / provably-absent / abort exit 3)
Task 8: fix round 2/5 (2 addressed, 0 open; commits c685aad..4a7c439; no new breakage)
Task 8: minor (deferred): a hard-killed list-devices probe aborts with raw exit 142 instead of the exit-3 shape (pre-existing gap, now bounded); live launch->poll->TIMEOUT->terminate path untested pending device pass
Task 8: complete (commits 5a71d9d..4a7c439, review clean after 2 fix rounds)
Gate note: commits after the formal gate (c685aad, 4a7c439) are scripts/mac/run-instrument.sh only — suite verdict at 9cc9285 stands for the tree's Swift content.
Task 9 (device witnesses): bar E sim arm WITNESSED (refused, alarm reason, witness/barE-sim-alarm-refusal.json). First iPad harness run earned two real fixes: 789094e (devicectl's REAL not-found stderr = "Failed to retrieve the file node"/CoreDeviceError 7000) and b755552 (fail-fast on refused launch). BLOCKED on physical unlock: the iPad is locked ("device was not, or could not be, unlocked"). Asking Owen.

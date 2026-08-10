# OPUS T27 — tooling bucket: #300 (lane-gate's wrong advice) + #319 (XcodeGen's wrong product name)

**Items:** OPEN_ITEMS **#300** + **#319**. **Difficulty: OPUS** — two small,
independent tooling fixes bucketed because neither fills a lane (the
#255-free-bucket pattern). Both touch infrastructure every lane depends on, so
the bars are stricter than the diffs. Written 2026-08-10.

## Half 1 — #300: `lane-gate.sh`'s failure advice misdiagnoses and cites a closed item

**Verified state (entry):** the gate's advice text classified a Swift Testing
failure THAT CARRIED ASSERTION TEXT as *"an XCUITest harness flake (NO
assertion text)"* and routed the reader to **#164 — CLOSED**, and about a
different test. Following it literally reopens a closed item under a wrong
diagnosis and re-rolls a real failure as noise — the gate's own founding sin
("absence of a failure marker is not success") running in reverse.

**Fix shape:** the classifier reads the PRESENCE of assertion text before
naming a cause (the discriminator #164's own tell already provides — that
flake's signature is the ABSENCE of assertion text), and the advice cites
items generically ("check the tracker for the XCUITest-runner flake family")
rather than by number — **a script cannot keep an item number live, so it
must not embed one.**

**Bars (copy into #300 before the edit):**
- **300-A (RED first):** feed the classifier the exact #254-lane failure text
  (a Swift Testing failure WITH assertion text) → it names an assertion
  failure, not a flake. RED on today's script.
- **300-B:** feed it a genuine no-assertion-text XCUITest bundle death → still
  classified as the runner-flake family (no regression on the true positive).
- **300-C:** grep the script for `#[0-9]+` — zero hardcoded tracker numbers
  remain in advice text.
- **300-D:** a clean run still passes the gate; a seeded failure still fails
  it (the gate's own self-test discipline — the #218 re-injection precedent).

## Half 2 — #319: XcodeGen rewrites `BuildableName` to the wrong product on every regen

**Verified state (entry + the 08-09 diagnosis):** every mandatory
`xcodegen generate` flips the scheme's `BuildableName` from `"Talaria 27.app"`
to `"Talaria.app"` — but `PRODUCT_NAME` IS `"Talaria 27"`, and `project.yml`
already carries an explicit `TEST_HOST` override compensating for the same
wrong derivation. Every lane that adds a Swift file hand-reverts this
(#272's fix lane did). **Owen asked about pinning; the answer stands: do NOT
pin the XcodeGen version — a pin freezes the bug** (Xcode stable at beta4
throughout; version drift refuted).

**Fix shape:** make regen idempotent — declare the scheme/product relationship
explicitly in `project.yml` (scheme `build.targets` + explicit product name,
or a generated-scheme stanza that carries `"Talaria 27.app"`), so the derived
name never appears. Investigate the 1.3→1.7 scheme-version bump and
`parallelizable="NO"` churn in the same pass — same root (generated scheme vs
hand-maintained scheme), likely same fix.

**Bars:**
- **319-A (the idempotency bar):** run `xcodegen generate` twice from a clean
  tree → `git diff` is EMPTY after the second run, and after the first run
  `BuildableName` still reads `"Talaria 27.app"` everywhere
  (`grep -c 'Talaria.app"' *.xcscheme` = 0 modulo the "Talaria 27.app"
  substring — write the grep to exclude it).
- **319-B:** the suite still builds and runs post-regen (the TEST_HOST
  override still resolves) — units + one XCUITest smoke.
- **319-C:** `GATE: PASS` on the regenerated project — proof the gate and the
  regen agree about the product name.

## Traps

- **#300:** the gate is the one script every verdict depends on — a wrong fix
  silently degrades every future reading (the entry's own warning). Test the
  classifier OUTSIDE the gate first (extract or source the function), then
  in place.
- **#319:** scheme files are XML the IDE also rewrites — verify 319-A from a
  clean checkout, not a working tree Xcode has touched mid-test.
- The two halves share NOTHING but size — land as separate commits so either
  can revert alone.

## Owen's to decide

Nothing pre-registered. If #319's fix turns out to require renaming
`PRODUCT_NAME` itself (the Option-B-flavored path), STOP — that touches the
display-name/Siri-phrase decision Owen explicitly deferred at the 2026-08-09
decision pass (purpose strings Option A), and it comes back as a question.

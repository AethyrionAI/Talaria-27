# Device Verification Checklist — 2026-07-11

Purpose: flip the built-unverified (🔧) backlog to ✅ — the #1 ROI item from the
2026-07-11 feature gap analysis. Scope is the standing verify backlog already in
`main`. Lane F (search/pin-archive) gets its section appended when its PR lands;
Lane G is relay pytest — **no device step**.

Source-of-truth rule: each item's real acceptance lives in its OPEN_ITEMS entry.
These are smoke tests to trigger the verify; if a step disagrees with the item's
stated acceptance, the item wins. AI output is a hypothesis — you are the gate.

Live-state note (2026-07-11): the merge train already flipped #39/#41/#44/#54 to
✅ — they are NOT in this list. #49 is stale (superseded by #91, theme suite
shipped) — close it into #91, don't verify it.

---

## 0. Preflight (toolchain trap guard — do this FIRST)

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27

# iOS 27 REQUIRES Xcode-beta. Default xcodebuild is 26.6 / iOS 26.5 SDK.
# Skipping this is the #1 cause of false "cannot find in scope" / "unavailable
# in iOS" errors — that's a wrong-Xcode smell, NOT an app-code bug.
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -version   # confirm the beta, not 26.6

git fetch origin --quiet && git status -sb   # know your branch before building
xcodegen generate

# MANDATORY post-xcodegen: aps-environment must survive the regen.
grep -A1 'aps-environment' Talaria/Talaria.entitlements || \
  echo "!!! aps-environment STRIPPED — stop, fix project.yml before proceeding"
```

---

## 1. Automated suites first (cheap, catch regressions before you touch the phone)

Run the `@Test` suites on the booted sim. These cover logic that doesn't need
real hardware (markdown parsing, router decisions, tool schemas).

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
SIM=47F68496-24F9-45D9-93D3-1C778DB6B557   # iPhone 17 Pro Max, iOS 27.0
LOG=/tmp/t27-tests-$(date +%H%M%S).log

nohup xcodebuild test \
  -scheme Talaria \
  -destination "platform=iOS Simulator,id=$SIM" \
  CODE_SIGNING_ALLOWED=NO \
  > "$LOG" 2>&1 & echo "PID=$!"; disown
# poll: sleep 30; tail -40 "$LOG"   (repeat — builds can run minutes)
```

Pass = Swift Testing's own line, NOT the XCTest summary:
```bash
grep -E '✔ .*Test run with [0-9]+ tests? passed' "$LOG"
```

**Model-gated suites must RUN, not skip.** Any suite behind FoundationModels /
Apple Intelligence (condenser fidelity, on-device titles) has to execute on
capable hardware — a green run full of skips is not a pass. If they skip on sim,
they move to the on-device pass below.

---

## 2. On-device manual checklist (REAL hardware — sim can't confirm these)

Build+install to the paired device (not sim) for this section. Each block:
trigger → pass criterion → the item to flip.

### #92 — Rich markdown + syntax-highlighted code (Lane B)
Ask Hermes for a reply containing a table, headings, a block quote, nested
lists, and a fenced code block in a named language.
- ✅ if: table renders as a grid; headings/quote/lists styled; code block is
  monospaced with syntax colors and horizontally scrolls without clipping.
- Flip #92. (This also unblocks #100 inline charts.)

### #60 — `_thinking` reasoning channel
Send a prompt that makes the model reason. Watch the stream.
- ✅ if: reasoning deltas appear in their OWN surface (collapsible/secondary),
  never folded into the final answer text. Answer stays clean.
- Flip #60.

### #61 — On-device auto titles + previews (FoundationModels)
Start a fresh conversation, send one substantive turn. (Needs Apple
Intelligence enabled + on-device model present.)
- ✅ if: the session auto-titles from content (no "New chat" placeholder) and
  the drawer preview is real text, not "—".
- Flip #61.

### #56 — "Ask Hermes" App Intent (Siri / Shortcuts)
"Hey Siri, Ask Hermes …" and also add the action in the Shortcuts app.
- ✅ if: the App Shortcut phrase fires the intent, Shortcuts exposes the action,
  and a long-running answer survives the ~25s intent handoff (returns/continues
  in-app rather than timing out silently).
- Flip #56.

### #58 — Control Center / Lock Screen controls + Action Button
Add the Hermes controls to Control Center and the Lock Screen; bind the Action
Button (needs iPhone 15 Pro+ hardware with an Action Button).
- ✅ if: each control deep-links into the right app surface (compose / Talk);
  Action Button launches the bound action from locked + from home.
- ⚠️ Hardware gate: no Action Button on the device → verify the CC/Lock Screen
  controls, mark the Action-button sub-item "hardware-pending," don't fake it.
- Flip #58 (or partial with the note).

### #67 / #68 — Local chat brain + cloud↔on-device router
Airplane mode (or kill the Hermes gateway), send a message.
- ✅ #67 if: a coherent reply comes from the on-device brain with no network.
- ✅ #68 if: with connectivity + "Automatic," routing picks cloud vs local
  sensibly and the seam is invisible (no dead-end when one side is down).
- Needs Apple Intelligence hardware + model. Flip #67 / #68.

### #69 — Device tool belt v1 (read tools for the local brain)
Ask the local brain a question needing device data ("where am I", "today's
step count", "am I moving").
- ✅ if: it calls the `hermes_mobile` read tools and answers from real device
  data — real values or an honest "—", never fabricated numbers.
- Flip #69.

### #70 — Action tools + ToolConfirmationCenter (confirm-gated writes)
Ask it to create a reminder / calendar event / alarm.
- ✅ if: a confirmation gate appears BEFORE the write; approving performs the
  real write; declining performs nothing. No silent side-effects.
- Flip #70.

---

## 3. Blocked / skip-until (do NOT attempt this pass)

### #73 — Native fallback voice mode  🚫 WEDGE-BLOCKED
Blocked by #82: the current iOS 27 beta seed breaks third-party audio capture
system-wide (reproduced outside Talaria, in Discord). Talaria is exonerated —
do not "verify" this now and do not chase it as an app bug. Retest on the next
beta seed; if still broken, that's the Apple Feedback repro (Talaria-free), not
a Talaria defect. The `#84` preflight build (c9e909e) stays unmerged and
`whoGoesThere` keeps that build.

---

## 4. Forward (not part of today's pass)

- **Lane F** (#96 search, #97 pin/archive): append a device section here when its
  PR lands — search-finds-known-entry, pin-floats-row, archive-hides-row, all
  surviving relaunch. Its `@Test` suites run in Section 1 first.
- **Lane G** (#98 scheduled runs): relay pytest, verified cloud-side. The only
  "device" touch is confirming a scheduled run's completion push arrives — fold
  that into the combined OJAMD deploy verification (see #98 deploy plan), not
  this checklist.

---

## Close-out

For every flipped item: edit its OPEN_ITEMS status 🔧→✅ with a dated "verified
on device 2026-07-11" note (OPEN_ITEMS commit separate from everything else per
house rule). Anything that fails: leave 🔧, capture the concrete failure
(log line / screenshot), and treat it as a fresh hypothesis to localize — don't
edit app code blind.

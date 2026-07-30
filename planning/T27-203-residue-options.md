# #203's residue — two product decisions, with options

**Written 2026-07-30 at Owen's request. The CoreLocation ship blocker itself is
FIXED and merged (PR #190, 15:10). What follows is what that fix deliberately left
open, because both are questions about what a stuck turn should look like to a
person — not questions about code.**

**No option here is implemented.** Each is costed so the choice can be made on
tradeoffs rather than on what is easiest to write.

---

## Decision 1 — production has no turn-level deadline of any kind

**What is true today.** #203 bounded the *location* wait at 10s. Every other way a
turn can hang is unbounded: a tool that never returns, a generation that stalls, a
confirmation card that is never answered. **The 35s guillotine exists only in the
battery instrument.** Production has nothing. A hung turn spins until the user
force-quits, and the UI gives no signal that anything is wrong.

**Why it is not obvious.** A deadline that fires wrongly is worse than none: it
would cancel a turn that was about to succeed, and #202B just showed how badly this
model handles being cut off from a tool it expected — it fabricates. **A timeout
that silently drops a tool mid-turn risks manufacturing exactly the lie we just
spent four lanes removing.**

### Option 1A — visible affordance, no cancellation *(recommended)*

After ~8s with no token and no tool event, show a quiet inline "still working…"
with a **Stop** control. Nothing is cancelled automatically; the user decides.

- **Cost:** small. One timer in the stream view, one state flag.
- **Risk:** near zero — it cannot cancel a healthy turn because it never cancels.
- **Leaves open:** a wedged turn still needs a human to notice it.
- **Why first:** it is the only option that adds information without adding a new
  failure mode, and every other option is easier to tune once we can *see* how often
  turns actually stall.

### Option 1B — hard turn deadline (e.g. 45–60s), cancel and surface

The whole turn is cancelled past the deadline and the user is told plainly.

- **Cost:** moderate. Needs cooperative cancellation the tools honour — and
  **#202-era work established a hung tool cannot be cancelled**, so this bounds the
  *generation*, not the tool.
- **Risk:** real. Picks a number with no data behind it. If the deadline is short,
  legitimate long turns die; if long, it barely helps.
- **Prerequisite:** 1A first, to learn the real distribution.

### Option 1C — per-tool deadlines only, no turn deadline

Extend `DeviceToolTimeout` (already built, 12s default) to every tool, and let the
turn run as long as it likes provided each tool answers.

- **Cost:** small — the mechanism exists and is already on Contacts and Places.
- **Risk:** low, and it targets the *measured* hang class rather than a hypothetical.
- **Gap:** does nothing for a stalled generation.

**My read: 1A + 1C together.** They are cheap, neither can kill a healthy turn, and
between them they cover the hang class we have actually observed while making the
unobserved one visible. 1B stays on the shelf until 1A produces data.

---

## Decision 2 — a dismissed permission dialog parks a waiter forever

**What is true today.** `locationManagerDidChangeAuthorization` returns early while
status is `.notDetermined`. A user who swipes the system dialog away without
choosing leaves the waiter pending with no resolution path.
**`ensureAuthorization()` is deliberately unbounded** — a machine deadline on a human
reading a dialog is unfair, and that reasoning still holds.

The question is not "how long do we wait" but **"what does the turn say when the
user never answers?"**

### Option 2A — treat dismissal as "not now", answer honestly *(recommended)*

If the app returns to foreground with status still `.notDetermined`, resolve the
waiter as *unavailable-this-turn* and let the turn continue.

- **Cost:** small. A foreground observer plus one resolution path.
- **Why it fits:** this is **exactly the shape #202D just promoted** — the honest
  refusal that names the turn rather than the capability, and points at a way
  forward ("ask me again once location is allowed"). The clause and the detector
  are already built and measured.
- **Risk:** a user who takes a long time deciding while the app is foregrounded is
  unaffected; the trigger is the foreground transition, not a clock.

### Option 2B — leave unbounded, add a visible indicator

Show "waiting for location permission…" with a cancel affordance.

- **Cost:** small, but it puts the burden on the user to notice and act.
- **Risk:** the turn still cannot complete on its own.

### Option 2C — pre-flight the permission before the tool is offered

Do not register location-dependent tools at all until authorization is settled.

- **Cost:** moderate — touches the belt-assembly path, which is load-bearing and
  well-pinned.
- **Risk:** changes what the model can see per turn, which is the seam #202 just
  spent four lanes measuring. **I would not touch it in the same week.**

**My read: 2A.** It reuses machinery that was measured today, it is the smallest
change, and it produces an honest sentence instead of a hang.

---

## What I would not do

**Do not bundle these with a measurement lane.** Every one of them changes
production behaviour on a path no battery covers, and #203's own lesson was that
splitting the ship-blocker fix onto its own branch was right — a production hang fix
should not be buried inside a measurement PR.

## Owed regardless of the choice

**A behavioural test for the location fix.** The existing pin
(`locationFixHasABoundedDeadline`) asserts only that a bounded, non-zero deadline
exists — it is deliberately weak and labelled as such. `DeviceLocationProvider` is a
concrete `CLLocationManagerDelegate` with no protocol seam, so the
generation-counted resume path cannot be driven from a test without a refactor.
**That refactor is the honest prerequisite to testing any of the above**, and it
should probably come first whichever option is chosen.

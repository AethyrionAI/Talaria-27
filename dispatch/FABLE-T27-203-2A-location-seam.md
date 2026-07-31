# FABLE — T27 #203 (2A): make the location provider's waiting behaviour testable, then prove it

**Routed by Owen 2026-07-31. This is a goal, not a recipe — the design is yours.
What follows is the context you need and the constraints that are non-negotiable.**

## The goal

**`DeviceLocationProvider` decides when a chat turn stops waiting, and none of that
behaviour can be driven from a test.** Give it a seam, then prove the three waiting
paths do what we believe they do. Right now they rest entirely on a careful read of
the code — and on this project, three separate readings of production turned out to
be wrong today until something actually ran.

## Why it matters

This class is load-bearing for a defect class we spent two days on. A turn that waits
forever is not a hang the user can diagnose — the app just sits there. #203 was filed
as a **ship blocker** for exactly this, and the fix that landed is unverified.

## What is in there now

`Talaria/Services/Live/DeviceTools/DeviceToolBelt.swift`, `@MainActor final class
DeviceLocationProvider: NSObject, CLLocationManagerDelegate`. Three waits, three
different policies, and the differences are deliberate:

1. **`currentLocation()` — bounded at 10s (`fixDeadline`).** #203's ship-blocker fix.
   CoreLocation can deliver neither `didUpdateLocations` nor `didFailWithError`, and
   the waiter used to park forever. A **generation counter** (`locationGeneration`)
   makes a fired deadline only ever affect the request it was armed for — that is the
   bug a naive timeout would have introduced, and it is the part most worth proving.
2. **`ensureAuthorization()` — deliberately UNBOUNDED by any clock.** It waits on a
   human reading a system dialog. **Do not put a timer on this.** It is not an
   oversight.
3. **The 2A addition (2026-07-31, unverified).** A dismissed dialog used to park the
   waiter forever, because `locationManagerDidChangeAuthorization` returns early
   while the status is `.notDetermined`. So the trigger is the **foreground
   transition**: if the app comes back with the status still undetermined, the user
   dismissed the dialog without answering, the waiter resolves `.notDetermined`, and
   callers already render that honestly as location-unavailable.

## Why it cannot be tested today

The class owns a concrete `CLLocationManager`, is its own `CLLocationManagerDelegate`,
and reaches `NotificationCenter` directly. **There is no seam to inject a fake.** The
one existing pin is deliberately weak and labelled as such:

```swift
@Test @MainActor func locationFixHasABoundedDeadline() {
    #expect(DeviceLocationProvider.fixDeadline > .zero)
    #expect(DeviceLocationProvider.fixDeadline <= .seconds(30))
}
```

That asserts a constant is in range. It says nothing about whether a waiter ever
resumes.

**The simulator does not rescue this.** A sim pass on 2026-07-31 confirmed the app
runs there, but FoundationModels ships no assets on the simulator, so on-device turns
fail instantly and never reach these paths in a realistic way.

## What "done" looks like

Behaviour proven, not constants checked:

- A fix that never arrives resumes the waiter at the deadline, once, with `nil`.
- A fix that arrives late — **after** its deadline already fired — does **not** resume
  a *later* request's waiter. This is what the generation counter exists for.
- A dismissed dialog (foreground returns, status still `.notDetermined`) resolves the
  waiter exactly once.
- A real decision arriving through the delegate resolves it exactly once, and the
  foreground observer is torn down.
- Multiple concurrent waiters all resume; none are stranded; none double-resume.
  (`CheckedContinuation` will trap on a double resume, so this is not cosmetic.)

## Constraints — these are the ones that will bite

- **Never put a machine deadline on a human wait.** The authorization wait and the
  action tools' confirmation-gate wait are both human. This principle is why 2A keys
  on a foreground transition rather than a timer, and it is not up for redesign.
- **Non-Sendable framework types must not cross concurrency boundaries.**
  `CLLocationManager`, `CMPedometer` and `MKLocalSearch` have all forced rewrites in
  this codebase already — construct them inside the closure and let only Sendable
  values out.
- **Keep the honest-failure shape.** When a wait ends without an answer, callers
  already say so plainly. #202D measured that a disarmed turn which *invents* an
  outcome is far worse than one that admits it, and #202C measured that a refusal
  claiming the *app* can't do something is its own kind of false. The sentence should
  be scoped to the turn, not the capability.
- **A refactor here must not change behaviour.** If the seam changes what production
  does, that is a separate, measured change.

## Freedom

The seam design is entirely yours — protocol, closure injection, a test-only
subclass, or something better. Same for how you drive time. Please do change the weak
pin above once real coverage exists; it was a placeholder and it is labelled as one.

## Related, if you want it — Owen has already routed this to Fable

**The tool-decode retry question (#197).** A `ToolCallError` kills the turn upstream
of the model, so the #176 recovery clause cannot engage. The raw-error *leak* is fixed
(only `tool.name` is surfaced now), but the turn still dies, and #208 falsified the
token cap as the cause. **The open question is whether one silent retry is a cure or a
coverup** — it would mask a decode failure we do not understand. That is a judgement
call about honesty, not a code question, which is why it is here and not in a lane.

## House rules

`OPEN_ITEMS.md` is the tracker (numbers there are a separate sequence from PR
numbers). `xcodegen generate` after adding files. `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`.
Owen routes every merge and promotion. **No Apple bug filing, ever** — standing rule.

# OPUS-T27-58 — SPIKE: why AppIntents extracts a nil URL from the control

**Item:** OPEN_ITEMS #58 (and #179, which shares the surface)
**Repo:** AethyrionAI/Talaria-27 · **Base:** main · **Branch:** none unless the spike concludes otherwise
**Output:** a written recommendation appended to #58. **NOT a PR.**
**Toolchain:** `export DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`

## Read this first

**This is a research spike, not a build task.** #58 has already consumed three device passes, each
spent implementing a fix against an assumption that turned out wrong. The tracker's own words:
*"Fix direction — needs scoping, not guessing."*

If you find yourself writing Swift before you have read Apple's current iOS 27 ControlWidget
guidance, stop. The deliverable here is knowing which fix is correct, not having written one.

## What is established — do not re-litigate

**The control is registered. Control Center invokes it. The extension spawns. `perform()` runs.**
Device log capture (`idevicesyslog`, whoGoesThere, `cbcc824`):

    17:25:39.803  chronod: Started executing LNAction OpenHermesChatIntent ... from control
                  openAppWhenRun: NO          <- PR #100's fix IS present and correct
    17:25:39.818  AppIntents: Invoking OpenHermesChatIntent.perform()
    17:25:39.818  TalariaWidgets: OpenHermesChatIntent.perform fired - opening hermes://chat
    17:25:39.819  AppIntents: OpenHermesChatIntent.perform() finished
    17:25:39.819  AppIntents: Prepared url to URL(nil))      <- THE DEFECT
    17:25:39.819  chronod: Successfully ran action

`perform()` logs a valid `hermes://chat` and AppIntents then extracts a **nil URL**.

**Stale control registration is EXCLUDED — confirmed twice.** The app was deleted and reinstalled
(which pulls the controls out of Control Center entirely), and Owen confirmed 2026-07-24 that he
went into Control Center and re-added both controls in order to test them. The `IMPORTANT CAVEAT`
previously attached to the 2026-07-23 observation is **resolved and retired**. Do not re-run this
triage step; do not treat registration as a live suspect.

**The #82 audio-wedge excuse for the Talk control is retired** — it fails for its own reason, and
#82's root cause was fixed in PR #106 anyway.

## The two candidate directions

**(a) Let the control launch the app via `openAppWhenRun`, and have the APP read the destination
from an app-group handoff** — decoupling launch from URL resolution entirely.

> **(a) directly contradicts PR #100's premise.** #100 set `openAppWhenRun: NO` deliberately. If
> you recommend (a), you are recommending that #100 was wrong, which is a defensible conclusion but
> must be argued explicitly against #100's reasoning rather than silently reversed.

**(b) Find an extension-side way to open a custom scheme that does not route through
LaunchServices.**

## What the spike must answer

1. **What is Apple's actual iOS 27 contract** for a `ControlWidget` action opening a URL? Read the
   current documentation and release notes. **Do not trust PR #100's note** — it predates the beta-4
   SDK and is the source of the assumption that burned three passes.
2. **Is `URL(nil)` expected** for a custom (non-universal-link) scheme from a control extension? If
   Apple simply does not permit custom schemes here, that decides the question and (b) is dead.
3. **Does `OpenHermesChatIntent` conform to the right protocol** for URL opening on this SDK, and is
   the URL surfaced via the property AppIntents actually reads? A conformance or property-name
   mismatch would produce exactly this signature — valid URL logged inside `perform()`, nil
   extracted outside it.
4. **What does #179 imply for either fix?** The first tap against a cold extension is swallowed
   entirely (success reported in 21 ms, no `PerformAction`, extension launched afterward). If that
   is Apple's cold-extension behaviour, **both (a) and (b) inherit it** and the fix needs a story
   for the first tap regardless of which direction wins.

## Deliverable

Append to OPEN_ITEMS #58, in its own file-scoped commit:

- the recommendation — (a), (b), or a third option the reading surfaced
- the evidence for it, with links to the specific Apple documentation consulted
- an explicit statement of what it means for PR #100 if the answer is (a)
- the first-tap story (#179), or an explicit note that it remains unsolved under this direction
- a size estimate, so it can be scheduled honestly

**If the reading is inconclusive, say so and stop.** An honest "Apple's guidance does not cover
this; here are the two experiments that would settle it" is a better outcome than a fourth
confident fix. This item's history is entirely made of confident fixes.

## Explicitly out of scope

Writing the fix. Touching `HermesControls.swift`. Any device pass — there is nothing to test until
a direction is chosen.

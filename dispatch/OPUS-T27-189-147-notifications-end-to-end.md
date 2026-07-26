# OPUS-T27-189 + 147 — notifications: ask for them, tell the truth about them, survive the tap

**Items:** OPEN_ITEMS #189 + #147 (touches #44, #31, #47) · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-189-147-notifications` · **Toolchain:** Xcode-beta4, pinned sim
**Baseline:** confirm the current green count before you start · `export GH_PAGER=cat` first

## SHIP BLOCKER (#189). Every notification feature is silently dead on a fresh install.

These are three defects on one user journey — never asked, lied to, then crashed. They share
`AppEntry.swift` and the notification diagnostics surface, so they ship together.

---

## Part 1 — #189: authorization is never requested

**Observed 2026-07-25.** Authorization status is `NotDetermined` — **not** `Denied`. The app has
never asked.

**Why it never fires.** The #31 contextual-priming trigger at `ChatStore.swift:408` is gated behind
`continuedSend != nil`, which only exists for messages **with attachments**. A user who sends plain
text and never watches a run detach is never prompted, ever.

**Fix:** a priming path that does not depend on attachments. Keep it contextual — #31's intent was to
ask at a moment the user understands, not at first launch. Pick a moment that every user reaches.
State the moment you chose and why.

## Part 2 — #189: the diagnostics panel reports a false green

The panel reports "active · relay registered" while authorization is `NotDetermined`. It reads
`UNAuthorizationStatus` **nowhere**. An APNs token and a relay registration row are both obtainable
*without* user authorization, so both can be true while notifications are entirely dead.

**This is a real-data-only violation** — the panel asserts a state it cannot see.

**Fix:** read `UNAuthorizationStatus` and report `NotDetermined` / `Denied` / `Authorized` honestly,
including the provisional and ephemeral cases if they are reachable. "Registered" and "authorized"
are different facts and must be displayed as different facts.

Related but distinct: **#44** closed on a truthful *push-token* readout. Token truth is not
authorization truth. Do not treat #44's verification as covering this.

## Part 3 — #147: the tap crashes the app

**REOPENED 2026-07-25.** Reproduced deterministically across multiple independent test runs on a
build containing the previous fix.

**Do not apply the fix named in the results doc — it is already in the crashing build.** `22f92e1`
annotated the *class* `HermesAppDelegate` with `@MainActor`. Both `userNotificationCenter` overloads
are declared `nonisolated` (`AppEntry.swift:124` and `:141`), which opts them back out. The
`nonisolated` annotations landed in `937e110` (2026-06-29) and `a2a1d88` (2026-07-05), weeks *before*
the fix; nothing has touched the delegate since. The `@MainActor` has been inert since it merged.

**The constraint, and read the comment at `AppEntry.swift:137–140` before touching anything.** The
`didReceive` overload is deliberately the **async** variant: the system awaits it and keeps the
possibly scene-less process alive for its whole duration, which is what the **#47** headless reply
path depends on. That guarantee must survive.

**The key observation:** the comment justifies the async variant by saying it has *"no completion
handler to send across an isolation boundary."* That is precisely why it does **not** need to be
`nonisolated`. The process-lifetime guarantee comes from the system awaiting an async method — it is
independent of which actor the body runs on. The `nonisolated` appears to have been carried over from
the `willPresent` overload, which genuinely does take a completion handler.

**Direction:** let `didReceive` inherit the class's `@MainActor` so its body — and the UIKit
state-restoration work that follows it — runs on main. Treat `willPresent` separately: it takes a
completion handler but only calls it synchronously with no actor-crossing state, so leaving it
`nonisolated` is defensible. **If you conclude otherwise, say so explicitly rather than changing it
silently.**

**Verify, do not assume:** confirm the #47 headless reply path still works after the change. A typed
reply from the notification action, app not running. That is the guarantee at risk.

---

## Definition of done

- Fresh install, plain-text-only usage: the user **is** asked for notification permission.
- Decline it: the panel reads `Denied`. Never grant it: the panel reads `NotDetermined`. Grant it:
  `Authorized`. **No configuration produces a green readout that is not true.**
- Tap a completion notification from a cold launch: the app opens to the right session and **does not
  crash**. Repeat from a warm launch.
- #47 headless typed reply still sends with no scene mounted.
- Deterministic tests where the surface allows. The crash itself needs a device run.
- Device verification is **owed by Owen** — state in the PR body exactly what to check, including the
  cold-tap case, since that is what was mis-verified last time.

## Process note — this is why #147 is here again

#147 was closed on a merge commit plus one device observation that most likely caught the #145 wedge
(the unbounded `openSession` await) rather than a fixed crash: a hang never reaches the completion
bridge, so the crash cannot fire. **An item closes on observed behavior on target, not on a merge.**
Write the PR body so the next person can tell which they are looking at.

## House rules

- Merge commits only, never squash. File-scoped commits.
- **OPEN_ITEMS.md edits in their own separate commit.**
- `xcodegen generate` only when Swift files are added or removed; pbxproj regen as its own commit;
  **verify `aps-environment: development` survived** — this lane touches push, so that check matters
  more than usual.

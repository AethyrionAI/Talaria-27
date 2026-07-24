# OPUS-T27-58A — Control Center launch via app-group handoff (option (a))

**Item:** OPEN_ITEMS #58 (touches #7, #179) · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-58-appgroup-handoff` · **Size:** ~30 lines + tests
**Toolchain:** `export DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`
**Baseline:** 1121 tests / 103 suites + 8 UI (post-PR #145)
**Staleness check:** `gh pr list --repo AethyrionAI/Talaria-27 --state all --limit 20` first.

## Why this shape, and why the obvious objection is wrong

The 2026-07-24 spike settled the diagnosis: **`OpenURLIntent` does not support custom URL schemes.**
Apple DTS states universal links are the supported mechanism; `hermes://chat` is rejected before it
reaches LaunchServices, which is the `AppIntents: Prepared url to URL(nil)` in the device log. Our
intents are textbook — the input is ineligible, not the wiring. Full reasoning is in #58.

**READ THIS BEFORE YOU OPEN `HermesControls.swift`.** Its in-source comment says pairing
`openAppWhenRun = true` with the returned `OpenURLIntent` made Control Center swallow the tap, and
"do not re-add it." **That comment is accurate about PAIRING them and is NOT an argument against
this lane.** With an `OpensIntent` result the returned intent IS the launch, so setting both makes
two mechanisms compete. This lane removes the `OpenURLIntent` entirely. **That combination has
never been tried.** Update the comment as part of the work — leaving it as-is will send the next
reader in a circle.

`HermesControlsTests` currently pins both intents to `openAppWhenRun == false`. **Those pins encode
the old conclusion and must be inverted, not worked around.**

## The change

For `OpenHermesChatIntent` and `OpenHermesVoiceIntent`, both in
`TalariaWidgets/Controls/HermesControls.swift`:

1. `static var openAppWhenRun = true`
2. `perform()` returns plain `some IntentResult` — **drop the `& OpensIntent` conformance and the
   `.result(opensIntent:)` return.**
3. Before returning, write the destination to the app group.
4. Keep `isDiscoverable = false` and the existing `controlLog.notice` — that logging is how #58 was
   diagnosed and it should keep naming the destination.

App side, in `AppEntry`: on launch/foreground, read the pending destination, clear it, and route.

## Use the existing app group — do not invent one

`SharedWidgetDataStore.appGroupID` already resolves the group (`APP_GROUP_ID` from Info.plist,
falling back to `group.org.aethyrion.talaria`) and both targets already use it — the widget
timeline provider reads it today. **Reuse that resolution.** A second hard-coded group string that
drifts from the first is a silent failure: the write succeeds into a suite nobody reads.

## Route through `handleDeeplink` — do not build a parallel path

`AppEntry.handleDeeplink(_:)` already switches on `hermes://` hosts — `chat`, `session`, `health`,
`briefing`, `voice` — and #17's Spotlight entities deliberately share it. **Store the URL and feed
it to `handleDeeplink`**, so the control path, Spotlight, Siri and Safari keep converging on one
router code path. Do not add a second switch; a divergent one WILL rot.

`hermes://voice` in particular sets `router.isVoiceOverlayPresented`, which `StartVoiceSessionIntent`
also sets — that equivalence is load-bearing and must survive.

## Consume-once, and tolerate absence

- **Clear the value as it is read.** A destination left in the group re-routes on the NEXT launch —
  a user who taps the control, quits, and reopens from the icon would be yanked to voice. Write the
  clear before the routing, not after.
- **A missing value must be a no-op, not a default route.** See #179 below. `handleDeeplink` already
  ignores unknown hosts; preserve that.
- **Consider staleness.** A timestamp alongside the destination, ignored beyond a short window, is
  cheap insurance against a value stranded by a crash between write and read. Judgement call —
  if you skip it, say why.

## #179 — expect a NEW symptom and do not misfile it

The cold first-tap swallow (#179) is extension cold-start behaviour, orthogonal to URL eligibility.
**This lane does not fix it, and it changes how it looks.**

With `openAppWhenRun = true` the system launches the app **even when `perform()` never ran**. So a
swallowed first tap will now open Talaria to the DEFAULT screen instead of doing nothing. That is
less broken than today and still wrong, and it will look exactly like a routing bug.

**This is why "missing value = no-op" is a requirement rather than a nicety.** Record the expected
behaviour in the PR body so the device pass does not file it as a regression of this lane.

## Tests

- Both intents now assert `openAppWhenRun == true` (replacing the inverted pins)
- Round-trip through the shared store: write destination → read → correct value, and the value is
  **gone** on a second read
- Absent value reads as nil and routes nowhere
- If a staleness window is added, one test either side of it

The intent `perform()` itself is not unit-testable from the app test target — state that limit
rather than faking coverage.

## Verification

1. `xcodegen generate` **only** if Swift files are added or removed; if run, verify
   `aps-environment: development` survived and commit the regen separately
2. Full suite on the pinned sim `47F68496-24F9-45D9-93D3-1C778DB6B557`, `CODE_SIGNING_ALLOWED=NO`
3. Report against **1121 / 103** and account for the delta
4. Long runs backgrounded: `nohup … & echo "pid=$!"; disown`, poll from a fresh shell

**The real verification is on device and is Owen's:** add the control to Control Center, tap it
(twice — the first may be swallowed per #179), confirm Talaria opens on the Chat tab; then the Talk
control opens the voice overlay. Note that in the PR as owed, not as done.

## Out of scope

**Option (c), universal links.** It is the shape Apple actually endorses, but it needs an AASA file
at a DOMAIN ROOT (the Pages site is a subpath today), the `associated-domains` entitlement — which
would join `aps-environment` on the must-survive-every-regen list — and app-side handling. It buys
the controls and nothing else, since `hermes://` still works from Safari, Shortcuts and Siri. If
this lane succeeds, (c) is unnecessary; recorded in #58 either way.

Also out: #179 itself, #58's Talk-control-specific behaviour beyond the launch, and anything in the
widget timeline provider.

## Commit discipline

File-scoped commits. pbxproj regen its own commit. OPEN_ITEMS.md separate from code.
`gh pr merge --merge`, never squash. `export GH_PAGER=cat` first.

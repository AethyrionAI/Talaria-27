# OPUS — #256 SETTINGS GRID STATUS STRIP + device-pass fixes

**Label:** OPUS · **Item:** OPEN_ITEMS #256 · **Written:** 2026-08-09

> **⛔ THIS IS A VERDICT, NOT A DISPATCH. #256 SHIPPED TO `main` ON 2026-08-05,
> IN TWO ROUNDS, AND ITS OWN ENTRY SAYS "Item is otherwise CLOSED."**
> Bars 256-A/B/C/D/F/G/H/I are MET. The only thing still owed is **half of one
> bar — 256-E's second clause** — a *passive* device observation that cannot be
> forced and must not be re-specced as work.
> Dispatching this item would respec merged, gated, device-judged code.

**Goal of this document:** record that #256 is complete, prove it at HEAD, carry
its pre-registered bars verbatim with their verdicts, and route the one genuinely
outstanding device observation into the existing device queue instead of
inventing a lane for it.

---

## 2. Verified state

### VERIFIED — both rounds are on `main`

| Commit | Round | What it landed |
|---|---|---|
| `2c17f86` | grid strip | Status strip, `SENSORS OFF` / `N LIVE` privacy value, sharpened past-due bounce, card value scale-to-fit |
| `c8b27fb` | verbiage | `CONNECTED` verbiage + voice card shows the engine route (256-G/H) |

Both confirmed on `main` via `git branch --contains`.

**The strip exists and is grid-only:**
- Rendered at `Talaria/Features/Settings/SettingsChannelsScreen.swift:222`,
  inside `gridScroll` — above `cardGrid`, below the top bar, exactly the
  placement Owen described.
- View body `SettingsChannelsScreen.swift:246-270`; identifier
  `settings.statusStrip` at `:270`; `MonoLabel` at size 10 (`:253`).
- Formatter `SettingsCardValues.statusStrip(...)` —
  `Talaria/Features/Settings/SettingsChannels.swift:103-119`.
- **Absent in deck mode by construction**, not by conditional: it lives inside
  `gridScroll`, which the deck branch does not render.

**Privacy value rewrite:** `SettingsChannels.swift:94-99`. Zero enabled streams →
`"SENSORS OFF"`; otherwise `"N SENSOR(S) LIVE"` with correct singular/plural. The
count is gated on the master flag, so a master-off install with three sub-toggles
remembered reads `SENSORS OFF` — which is the true statement.

**Verbiage round:** `uplink()` at `SettingsChannels.swift:51-58` — online+direct →
`"CONNECTED"`, relay → `"RELAY"`. `voice()` at `:76-85` — the full three-way
route with the voluntary/forced distinction Owen asked for.

**Test coverage is real:** `TalariaTests/SettingsChannelsTests.swift` — 13 `@Test`
cases, strip composition pinned across five shapes at `:75-95`. XCUITest asserts
the strip **present in grid** (`TalariaUITests/AppTemplateUITests.swift:466`) and
**absent in deck** (`:515`) — the 256-C pair, and the correct way to pin a
mode-scoped element.

### VERIFIED — the honesty properties hold

The strip is the app's most prominent single line of live telemetry, so it is
worth stating that it does not lie:

- **Unknown host → `"—"`**, never a guess — `SettingsChannels.swift:112`, whose
  own comment reads *"unknowable hosts render `—` (real data only)."*
- **Hostless collapses to the on-device story** rather than emitting `—` noise
  for a host that was never supposed to exist (`:107-110`) — honoring #252's
  routed constraint that unpaired is the DESIGNED state, not a deficiency.
- **`RELAY` is flagged, `DIRECT` is silent** (`:114-117`). The reasoning in the
  code comment is sound: direct is the norm, so naming it every time answers a
  question users don't ask; relay is the anomaly worth surfacing. This also ages
  correctly — the DIRECT/RELAY distinction dies with #251 Phase 4, and only the
  anomaly branch will need removing.

### VERIFIED — what remains open

**One half of one bar.** #256's entry states it precisely:

> *"every #256 bar is MET except 256-E's second half — the sharpened reminder
> phrasing (evening 'remind me at 8' should now come back OFFERING tonight) —
> which stays open until his next natural reminder ask."*

256-E's first half (strip reads correctly, grid sits lower) was MET on build 2042:
*"Strip looks good. Good on width, I imagined it larger, but i'm ok with this."*
256-I was MET on build 2047, PR #271: *"strip looks good, voice looks good,
privacy looks good."*

**There is a second, sibling observation owed from #249F**, and the two should be
watched together because one evening reminder can settle both:

| Owed | From | The bounce path | What Owen should see |
|---|---|---|---|
| 256-E (2nd half) | #256, `2c17f86` | **past-due** | evening "remind me at 8" comes back **offering tonight** |
| 249F-D | #249, PR #273 `ca895f2` | **evening-clock** | reply asks **tonight-or-tomorrow** and claims **nothing was set** |

These are two different code paths sharpened in two different lanes eight hours
apart, and both are waiting on the same trigger. **Neither is currently in
`dispatch/DEVICE-PASS-RUNNING-LIST.md`** — verified by grep: that file contains no
mention of #256, #252, or #249. That is a routing gap, not new work (§6).

### ASSUMED (stated, not verified this pass)

- **Suite green at HEAD.** #256's last recorded gate was `GATE: PASS` — 1618
  units + 12 XCUITest + Release. `main` has advanced far since (the #297 lane
  reports 1852 units). No gate was run by this document.
- **256-D's device judgment** (Appearance card, longest theme name, no ellipsis)
  is recorded as riding along *"informally (nothing ellipsized in his passes)"*.
  Scale-to-fit is built at 0.65 minimum. Treated as settled; not re-verified.
- **The phone's current build.** The device batch note says OTA 2250 was staged
  from `main` `29fa34a` and then superseded. Whatever build Owen is on must be at
  or past `ca895f2` for 249F-D to be observable at all — §6 flags this.

---

## 3. The #252 ↔ #256 relationship

**VERDICT: (a) — #256 is a stepping stone that SURVIVES #252 completely, because
#256 was built ON #252's new surface, not on the grid #252 replaced. Nothing is
thrown away. Both shipped, in the correct order, twelve hours apart.**

The framing worth correcting: this was not "a strip on the old grid, about to be
obsoleted by a redesign." The redesign landed **first**, Owen used it on device,
and #256 is the punch-list his device pass generated.

**Evidence:**

1. **#256's strip is physically inside #252's file.** `settings.statusStrip` is
   rendered at `SettingsChannelsScreen.swift:222` — the screen `20b85b4`
   introduced. It could not have been built before #252 landed.
2. **#256's charter is quoted from #252's device pass.** #252 entry, verdict (f):
   *"INFO STRIP APPROVED: the grid sits too high; a full-row status bar (~two
   cards wide) between the top bar and the grid 'would move it down perfectly'."*
3. **#256 fixes strings #252 shipped.** #252 verdict (d) records `"0 STREAMS"`
   REJECTED on device (*"doesn't clarify what it is, would drive me nuts"*);
   `SettingsChannels.swift:92-93`'s comment names #256 as that rejection's
   remedy. Same for the Appearance truncation ride-along.
4. **Commit order proves the sequence.** `20b85b4 → fff72bf → a73ea09 → f8badf7
   → c470631 → c47a91b` (#252), then `2c17f86` and `c8b27fb` (#256).

**Shipping order: already correct and already executed — #252 first, #256
second.** No re-sequencing is available or needed.

**On the standing lesson** (a fix on a component with a planned end-of-life buys
reliability that expires): it does **not** apply to this pair, and saying why
matters. That rule bites when hardening a doomed sidecar. #256 spent its effort
on the *replacement* surface using the first real device feedback about it —
the healthiest possible timing. The one place the rule genuinely applies inside
#256 is the strip's `RELAY` branch, which #251 Phase 4 will delete; the code
already anticipates that (`SettingsChannels.swift:114-117` treats direct as
unmarked so only the anomaly branch needs removing).

**The one coupling that is NOT clean:** #256-H changed the Voice card's value
semantics (read-aloud toggle → engine route) but left #252's Voice **accent**
predicate reading `readAloudAutoPlay` — `SettingsChannelsScreen.swift:417`. The
card's glow and its text now describe different facts. Full analysis and a
proposed bar are in `dispatch/OPUS-T27-252-settings-channels.md` §2/§5 (bar
252R-A). It is filed there because the accent predicate is #252's code, even
though #256's change is what orphaned it.

---

## 4. ⚠️ Tracker corrections

Owed against `OPEN_ITEMS.md` **#256**. **This document does NOT edit that
file** — the orchestrator files these.

1. **The header is stale in the same way #252's is.** `OPEN_ITEMS.md:7765` reads
   *"ROUTED 2026-08-05 night… bars pre-registered below BEFORE the run"* — the
   state of an item about to start, on an item whose body says *"Item is
   otherwise CLOSED."* Proposed: **✅ CLOSED 2026-08-05 (256-A/B/C/D/F/G/H/I MET,
   two gate PASSes, device-met on builds 2042 and 2047) — OPEN only for 256-E's
   second half, a passive device observation.** Board index `OPEN_ITEMS.md:193`
   needs the same. The close-out rule's target exactly.
2. **256-E's bar text was superseded by 256-G and should say so in place.**
   256-E was written expecting the strip to read
   `LINKED · DIRECT · OJAMD · DEEPSEEK-V4-FLASH`. 256-G — routed later the same
   night by Owen — **removed the transport word from the direct case**, so the
   shipped strip reads `LINKED · OJAMD · …`. The bar as written can never be met
   literally. This is a legitimate later routing decision superseding an earlier
   bar, **not** a missed bar and **not** a redefinition-after-the-fact — but the
   supersession must be annotated at 256-E's own text, upstream, or a future
   reader will score it as a miss. Suggested inline note: *"(strip text
   superseded by 256-G — the direct case drops `DIRECT`.)"*
3. **The two owed device observations are not in the device queue.**
   `dispatch/DEVICE-PASS-RUNNING-LIST.md` has no #256/#249 rows (verified by
   grep). Both #256's entry and #249's say the observation *"rides the next
   OTA"*, but that instruction lives only in `OPEN_ITEMS.md`, and the running
   list is the file the device sittings are driven from. §6 supplies the rows.
4. **No falsified CLAUDE.md line found.** The Design system section's claims —
   palettes in `Shared/ThemePaletteCore.swift`, `ThemeRuntime` resolving live,
   HUD components in `Talaria/Core/HUD/` — all hold against the new settings
   surface, which consumes `MonoLabel`, `Design.Brand.*`, `Design.Colors.*` and
   `.hudGlow` unmodified. Nothing to correct there. Stated because the close-out
   rule requires the check, not because it found something.

---

## 5. Bars

### CARRIED VERBATIM from `OPEN_ITEMS.md` #256 — pre-registered before the run, transcribed unchanged

> - **256-A (unit):** privacy formatter — 0 → "SENSORS OFF", 1 →
>   "1 SENSOR LIVE", 3 → "3 SENSORS LIVE".
> - **256-B (unit):** new past-due bounce pins — still leads "No reminder
>   was created", carries the next-occurrence steering phrase, still no
>   digits or formatted date (233-E); the latch/caution path is unchanged
>   (existing 249 tests stay green with only wording pins updated).
> - **256-C (UI):** grid shows `settings.statusStrip` with store-derived
>   link/host/model text; strip absent in deck mode.
> - **256-D (build + device):** Appearance card value renders the longest
>   catalog theme name without ellipsis (scale-to-fit); Owen judges on
>   device.
> - **256-E (device, Owen):** strip reads LINKED · DIRECT · OJAMD ·
>   DEEPSEEK-V4-FLASH on his paired install and the grid sits visibly
>   lower; an evening "remind me at 8" now comes back offering tonight.
> - **256-F (ride-along, added same night from Owen's #250 follow-up
>   screenshot, before its code):** the Appearance deck page's APP ICON
>   row becomes a NavigationLink to the icon gallery
>   (`settings.appearance.openIconGallery`) — the gallery was findable
>   only via browser → tuning → expand. GLOW/GRID rows stay read-only.
>
> - **256-G (unit):** uplink card online+direct → "CONNECTED" (relay →
>   "RELAY", other states unchanged); strip drops the transport word for
>   the direct case → "LINKED · OJAMD · DEEPSEEK-V4-FLASH", keeps the
>   anomaly → "LINKED · RELAY · …".
> - **256-H (unit):** voice route formatter — brain on-device →
>   "ON-DEVICE" (voluntary); engine picked .native on a linked brain →
>   "LOCAL" (voluntary); talk .connected → "REALTIME · LIVE"; .ready /
>   .connecting → "REALTIME"; .checking → "…"; .idle/.blocked/.failed on
>   a linked brain → "LOCAL ONLY" (the forced-fallback indicator).
>   Read-aloud state demotes to the Voice deck page (already there).
> - **256-I (device, Owen):** Uplink reads CONNECTED; Voice card shows
>   the route and flips to ON-DEVICE when he switches the brain.

**A missed bar is a falsification, not a redefinition.**

### Verdicts as recorded (do not re-run)

| Bar | Verdict | Evidence |
|---|---|---|
| 256-A | **MET** | privacy formatter pins, watched RED then GREEN |
| 256-B | **MET** | bounce pins updated, latch/caution path untouched |
| 256-C | **MET** | XCUITest pair — `AppTemplateUITests.swift:466` / `:515` |
| 256-D | **built**; device judgment informal | scale-to-fit 0.65; nothing ellipsized in Owen's passes |
| 256-E | **half MET** | build 2042: *"Strip looks good… i'm ok with this."* **Second half OPEN** |
| 256-F | **MET** | deck APP ICON row → gallery, `settings.appearance.openIconGallery` |
| 256-G | **MET** | 13/13 formatter suite; direct case `LINKED · OJAMD · …`, RELAY still flagged |
| 256-H | **MET** | three-way route; grid fires `refreshReadiness()` so the card is live |
| 256-I | **MET** | build 2047, PR #271: *"strip looks good, voice looks good, privacy looks good."* |

Two gate passes on record, both `GATE: PASS` — 1618 units + 12 XCUITest +
Release, each round.

### The real-data bar for this surface — already satisfied, stated for the record

The nine-card live-telemetry grid is where CLAUDE.md's *"Real data only in UI —
show `—` where a value isn't knowable; no mocked toggles"* bites hardest, so it
should be checkable rather than assumed. **It holds at HEAD**: every card value
and every strip segment is store-derived
(`SettingsChannelsScreen.swift:374-409`), unknown host renders `"—"`
(`SettingsChannels.swift:112`), an unloaded session count renders `"…"` rather
than a false `0` (`:121-122`), and a checking voice route renders `"…"` (`:82`).
No literal telemetry survives anywhere in the surface.

**The forward-looking version of this bar is filed as 252R-A** in the companion
document — it extends real-data honesty from card TEXT to card ACCENT, which is
the one place the surface currently misleads.

---

## 6. Task breakdown

**No build tasks. #256 is code-complete.** Two administrative tasks:

1. **Route the two owed device observations into the existing queue.** Append to
   `dispatch/DEVICE-PASS-RUNNING-LIST.md` — do **not** open a parallel queue,
   and do not create a lane. Ready-to-paste, passive, zero forced tests:

   > ### R1 · #256-E (2nd half) + #249F-D — reminder phrasing, PASSIVE
   > **Prerequisite:** a build at or past `ca895f2` (#249F, PR #273). OTA 2250
   > and anything staged after it qualifies; confirm before counting a reading.
   > **No forced test — observe on the next NATURAL evening reminder ask.**
   > One ask can settle both if the time is ambiguous (e.g. "remind me at 8"
   > said in the evening).
   > - **256-E (2nd half):** an evening "remind me at 8" comes back **offering
   >   tonight** rather than silently resolving to a past or next-day hour.
   > - **249F-D:** the reply asks **tonight-or-tomorrow** and makes **no claim
   >   that anything was set** — the false-positive direction is the dangerous
   >   one (user believes a reminder exists, relies on it, misses the call).
   > **Record the model's exact words**; both bars are text bars, and the
   > failure mode they guard against is a *mined phrase*, not a wrong time.

2. **File §4's tracker corrections** into `OPEN_ITEMS.md` #256 — header state,
   256-E's supersession note annotated in place (upstream, at the bar's own
   text), and the device-queue cross-reference.

**`xcodegen generate`: not needed.** This document adds and removes no Swift
files. (Noted because the #252 redesign that preceded it *did* add four and
delete two, and regeneration was mandatory there.)

---

## 7. What is OWEN'S to decide

1. **Whether 256-E's second half stays open at all.** It is a passive
   observation on a text change that is unit-pinned and gated. Options: keep
   watching (costs nothing, settles on the next natural ask), or close #256 now
   and let #249F-D carry the reminder-phrasing verdict alone — the two overlap
   substantially. Recommendation: **close #256, keep 249F-D**, since 249F-D is
   the strictly stronger bar (it also forbids the false success claim).
2. **The Voice accent question** — see `dispatch/OPUS-T27-252-settings-channels.md`
   §7.2. Should the Voice card glow for any live route, or only for a connected
   realtime session? This is the last decision #256's verbiage round left open.
3. **Strip width, revisited.** Owen accepted it with a reservation:
   *"Good on width, I imagined it larger, but i'm ok with this."* That is an
   accepted-not-preferred verdict. If he wants it larger, it is a one-line
   change at `SettingsChannelsScreen.swift:253` (MonoLabel size 10) — cheap
   enough to bundle with 252R if that lane runs.
4. **Whether `LINKED` should survive #251 Phase 4.** #256's own filed musing
   notes the DIRECT/RELAY distinction dies with the relay. The code is already
   shaped for that deletion; the question is only whether `LINKED` remains the
   right word once there is nothing to be linked *through*.

---

## 8. Traps

- **Shipping a fix into a surface about to be replaced.** The trap this pair was
  screened for, and it **did not occur** — #256 built on #252's replacement
  surface, not on the grid #252 deleted. But the reverse error is live and
  cheap to make: cancelling #256 on the theory that a redesign will eat it.
  The commit order (`c47a91b` → `2c17f86`) is the check that settles it in five
  seconds. Run the check before believing either story.
- **Both `HermesWidgetData.swift` copies.** #256 touched no widget code. If any
  follow-on does, the app-target and widget-target copies must move in
  lockstep — `appearanceTheme` in particular. A one-sided edit compiles cleanly
  and diverges silently, which is the worst combination available.
- **Theme resolution is live.** The Appearance card value composes
  `ThemeRuntime.shared.theme.displayLabel` with a live channel index
  (`SettingsChannels.swift:87-90`). Any pin on that string is really a pin on
  theme-catalog data in `Shared/ThemePaletteCore.swift`; adding a theme changes
  it. Never hardcode a palette value.
- **The strip is grid-only by placement, not by an `if`.** It sits inside
  `gridScroll` (`SettingsChannelsScreen.swift:222`). A refactor that hoists it
  for layout reasons will silently break 256-C's "absent in deck" half — and
  that half is asserted with `XCTAssertFalse` (`AppTemplateUITests.swift:515`),
  which passes trivially if the element is renamed rather than removed. Keep the
  identifier stable.
- **A "verified" device bar with no build number is not verified.** 249F-D needs
  a build at or past `ca895f2`; 256-E's second half needs `2c17f86`. An
  observation on an older build reads as a miss when it is really a
  configuration error — the #215-family mistake of measuring a configuration the
  app never entered.
- **`-only-testing` selectors that match nothing report `TEST SUCCEEDED`.** Both
  variants have burned this project — a nonexistent class name (#252's
  correction of record) and a METHOD path under a Swift Testing struct (#249F).
  **Read the executed count, not the marker.**
- **`test-without-building` re-runs stale `.xctest` binaries** and reports green
  at the OLD test count. After editing tests, confirm the count MOVED.

---

## 9. Close-out

**This item does not need a lane. It needs its header corrected and two device
rows added to a queue that already exists.**

#256 delivered everything Owen routed: the strip, the Privacy rewrite, the
bounce sharpening, the Appearance truncation fix, plus a whole second round
(CONNECTED, voice route) that he specified and judged on device the same night.
Eight of nine bars MET with recorded evidence, two gate passes, two device
confirmations in Owen's own words.

What it did not do is close itself out. Its header still announces work about to
begin; 256-E's bar text still describes a strip format that 256-G superseded
hours later; and the device observation it deferred *"to the next OTA"* was never
written into the file the device sittings are actually driven from. All three are
§4/§6 items, and by the close-out rule they belong in one commit.

**Recommendation to the orchestrator:** file §4's corrections, append §6's R1 row
to `dispatch/DEVICE-PASS-RUNNING-LIST.md`, and put both #252 and #256 to bed. The
only code worth writing out of this pair is bar **252R-A** — the Voice card's
accent, ten lines and a unit pin — and even that is Owen's call, not a default.

**Cross-reference:** `dispatch/OPUS-T27-252-settings-channels.md` (companion
verdict; #252 likewise shipped, carrying the one residual code defect).

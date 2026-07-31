# OPUS T27 #209 — make `metric` and `place` optional, and say plainly why there is no efficacy bar

**Written BEFORE the change landed, per the standing rhythm. The unusual part is
that this dispatch pre-registers NO efficacy bar, and the reason is the point.**

## What changed

`DeviceHealthTool.metric` and `WeatherTool.place` become optional, each with a
pinned rollback twin (`DeviceHealthToolRequiredMetric`, `WeatherToolRequiredPlace`)
carrying the identical name, description, `@Guide` text and engine — schema is the
only delta. Same shape as #200S (remind `due`/`list`) and #200X (calendar
`durationMinutes`/`location`).

## Why, with the evidence

Pooled over the 48 retained run JSONs: **13 of 13** `ToolCallError` causes are
`GeneratedContent does not contain a property 'X'`. Five were `metric` with the
model emitting `{}`; two were `place`, also `{}`.

`currentWeather` is the starkest: its `@Guide` has said **"Optional… Leave empty
for the user's current location"** since it shipped, while the type said required.
The model obeyed the prose and the turn died. That is week-plan finding 3 —
when behaviour resists an instruction, look for a structural constraint saying the
opposite — and here the contradiction was written into the same declaration.

Both fields are genuinely defaultable, and both defaults ALREADY EXIST in `call()`:
`wantsMetric` reads empty as "all of them", and an empty place means here. So a
well-formed call cannot change behaviour; only the broken ones change, from a dead
turn into the answer the user asked for.

**`title` is deliberately NOT included.** Four reminder trials and one calendar
trial died on a missing `title`, and the reminder payloads show the model had
already produced `due` and `list` and dropped only the field carrying what the
reminder is *about*. A defaulted title invents user data, which #202D measured as
the worst available failure mode. The rule stands as `DeviceActionTools` states it:
**the schema should demand exactly what the tool cannot default.**

## NO EFFICACY BAR — and this is a pre-registration, not an excuse

The disease's own rate makes a treatment/control battery unevaluable:

| cell | rate |
|---|---|
| `armed/haiku` (largest affected cell) | **5/350 = 1.4%** |
| pooled, haiku prompt | 0.92% |
| pooled, calendar prompt | 0.53% |
| pooled, remind prompt | 0.13% |
| alarm / norway / canary | 0.00% |

At n=30 an arm expects **0.4** occurrences. Both arms read zero, the bar "holds",
and the run means nothing. **Writing an efficacy bar here would be the #201
mis-specification for the fifth time** — an evaluability gate sitting above the
disease's own rate. #208 closed a lane in four minutes by asking whether the
instrument could see the thing at all; this asks the same question first.

## What IS pinned, instead

`TalariaTests/RequiredPropertyDecodeTests.swift` replays the **exact recorded
payloads** through `GeneratedContent(json:)` and asserts, for each pair, that the
promoted schema accepts what the rollback twin still refuses. The guarantee is
structural — the failure class becomes *impossible*, not *rarer* — so a
deterministic test is the honest instrument and a battery is not.

Precedent that this works: `CalendarEventToolRequiredFields` threw
`does not contain a property 'durationMinutes'` in the records while the promoted
tool never did. That pair is pinned too, so #200X's guarantee cannot regress.

## ADDENDUM — the read-tool battery, and why a bar IS writable after all

**Written before the run, same as everything above.**

The "no efficacy bar" conclusion was correct for the prompts we HAD, and wrong as
a general statement. The 1.4% figure comes from failures on **spurious** calls —
the model grabbing `readHealth` during a haiku, or `currentWeather` during a
calendar request. On those, the model had no reason to omit the field and mostly
didn't.

**Turn it around.** "What's the weather?" names no place. "How am I doing today?"
names no metric. On prompts like these, **emitting `{}` is what a correct model
should do** — and the pre-#209 schema forbade exactly that. The right response to
an instrument that cannot see the disease is to provoke the disease, not to lower
the bar until it fits.

`Read-tool battery n=10 (80)`: `[.armed, .armedFieldrollback]` × 4 prompts × 10.
Read tools only, so nothing is written and the reap is a no-op.

| tag | prompt | field available to fill? |
|---|---|---|
| `weatherbare` | "What's the weather?" | **no** — omission is correct |
| `weathernamed` | "What's the weather in Biloxi?" | yes — control |
| `healthbare` | "How am I doing today?" | **no** — omission is correct |
| `healthnamed` | "How many steps have I taken today?" | yes — control |

### Pre-registered bars

**Evaluability gate (must clear first, or nothing below is readable):** the
ROLLBACK arm must show **≥3 of 20** missing-required-property errors pooled across
its two bare prompts. Below that, the mechanism is rarer than this lane believes
even under direct provocation, the run is **INCONCLUSIVE**, and no comparison is
reported. Deliberately set UNDER the effect this design is built to elicit rather
than over it — #201 was mis-specified four times by inverting exactly this.

**Primary:** production shows **0** missing-required-property errors on the bare
prompts. Any at all falsifies the structural claim that the failure class is now
impossible, and that outranks every rate in this run.

**Control (guards against the wrong mechanism):** the two `-named` prompts should
behave the SAME in both arms. If the rollback arm fails those too, the failure is
not about omission and this lane's story is wrong.

**Answer quality, not just survival:** a production `weatherbare` turn should
return weather for the current location, and `healthbare` should return the
summary — not an error sentence. Surviving the decode is not the same as
answering, and #202D is the standing reminder that a turn can complete and still
be worthless.

## The bar that IS pre-registered: NO REGRESSION

On the next battery that runs for any reason, against the standing #200K-pattern
bars: **pooled remind ≥17/20, alarm 20/20, calendar ≥14/20.** If any falls, this
change is implicated and reverts to the twins. That is a real bar at a rate the
instrument can actually see.

## Rollback

Swap `DeviceHealthTool` → `DeviceHealthToolRequiredMetric` and `WeatherTool` →
`WeatherToolRequiredPlace` in the belt. Byte-identical to pre-#209 production.

## House rules

`OPEN_ITEMS.md` is the tracker (its numbers are a separate sequence from GitHub's).
`xcodegen generate` after adding files. `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`.
Owen routes every merge and promotion. **No Apple bug filing, ever.**

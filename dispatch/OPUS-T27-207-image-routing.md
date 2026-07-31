# T27 #207 — the router cannot see that an image is attached

**Owen routed this. Bars written BEFORE any code. Classified from the run JSON.**

## Why this run exists

**Measured in run `86A29FD8`: image turns route TOOLLESS, 0/15 and 0/15.** A photo
plus "what does this say?" gets a turn with **no belt** — so it reaches neither the
model's vision (it has none; the transcript carries a placeholder) nor
`readImageText` / `BarcodeReaderTool`. **The app has the capability and the turn
cannot reach it.** Clause v2 at least makes it fail honestly now instead of
fabricating, but honest-and-useless is still useless.

**And the measurement was GENEROUS.** Those probe rows read
`[image attached] what does this say?`. **Production never generates that marker.**
`preparedSession` calls the router with `prompt: nextPrompt` — the user's raw typed
text — while `attachments` sits in scope and `hasImage` is computed **six lines
below** and never passed. So production hands the router *"what does this say?"*
with no image signal at all. **Production is at least as bad as 0/15, probably
worse**, and the first row set below measures exactly that.

## The two seams, and why they are separable

1. **SIGNAL** — the router is not told an image is attached. Pure plumbing:
   `hasImage` already exists a few lines away, and #202D threaded the prior
   assistant turn through this same call.
2. **TEXT** — the pinned `@Guide` enumerates device data and device actions and
   **never mentions images or photos**.

**They are measured separately and in that order**, because the signal may be
sufficient on its own: told an image is present, the router may already route armed
without any wording change. **If it does, the `@Guide` stays untouched** — and that
matters, because #196 established that guide-only framing misrouted *every creative
verb*, and this text is a measured artifact with a 200/200 history.

## Grid

Every row runs on **production's router (`ctx-a`)**, contextless — an image turn is
typically a fresh request.

**IMAGE band (expected ARMED), 4 rows** — with and without the marker, so the
production shape is measured rather than assumed:

- "what does this say?" · "read the text in this photo"
- "what's in this picture?" · "scan this barcode"

**Three arms:**

| arm | seam |
|---|---|
| **img-none** | production today: raw prompt, no image signal. **The true production baseline.** |
| **img-signal** | prompt prefixed with an image marker; `@Guide` UNCHANGED |
| **img-guide** | image marker **plus** the `@Guide` gains images/photos |

**COLLATERAL band — the #196 baseline grid, all ten rows, on every arm.** The
`@Guide` is a pinned artifact with a 200/200 history; any arm that touches it must
prove it did not disturb the rest. **This is the bar that can kill img-guide.**

**Cost:** (4 image + 10 baseline) × 3 arms × n=10 = **420 classifications ≈ 5 min**
at the ~0.6s/route measured. Cheap, no writes, nothing to reap.

## Bars

**BASELINE / REPRODUCTION GATE:** `img-none` must route the image rows toolless in
**≥ 3 of 4 rows**. That is the defect as filed; if production already routes these
armed, the premise is wrong and **that is the headline** — the lane closes and the
0/15 gets re-read.

**PRIMARY (img-signal):** ≥ **3 of 4** image rows route ARMED. If the signal alone
clears it, **img-guide is not promoted even if it also passes** — the smaller change
wins on parsimony, exactly as ctx-a beat ctx-b in #202A.

**SECONDARY (img-guide):** only read if img-signal FAILS. Same ≥3/4 bar.

**COLLATERAL GATE — the one that kills an arm:** the #196 baseline must hold at
**≥ 95% (≥95/100 per arm)**. It has been 200/200 twice and 150/150 today. **An arm
that fixes images by arming everything is not a fix**, and it re-opens #196 — the
degenerate this program has now named in advance four times.

**REPORTED, NOT GATED:** the marker-vs-no-marker contrast within `img-signal`. If
the marker is what does the work, production must be changed to emit one; if the
bare prompts route armed once the arm is otherwise identical, that is a surprise
worth recording.

## Determinism, stated in advance

**The router decodes GREEDILY, so repeating one row re-measures one sample** (#202A,
where all 49 rows saturated). n=10 buys confidence against transient failure, not
statistical power. **The honest denominator is the ROW COUNT — 4 image rows, 10
baseline rows per arm** — and the classifier already detects saturation and says so.
Bars above are written in rows for exactly this reason.

## Rollback

Whichever arm promotes, its rollback is the flag's `false` — the signal is a
parameter default and the `@Guide` addition is a Bool, each byte-identical when off,
and each reachable as a measured cell. Same shape as every promotion since #200D.

**No Apple filing** — standing rule.

# OPUS T27-296C1 — the host's Boolean `error` is dropped by the parser; a DENIED tool renders as a clean ✓

**Item:** OPEN_ITEMS **#296** (296-C1, REOPENED by the wire). **Difficulty:
OPUS** — a two-site type fix with the evidence already gathered; the tests are
the work. Written 2026-08-10.

## 1. Verified state

- **The wire fact (probe, 2026-08-09, Mac `:8642`; pre-registered as a
  discovery probe):** the host DOES populate `error` on `tool.completed` — as
  a **BOOLEAN** (`error: true`), not a string.
- **The parser drops it — two sites, verified at HEAD 2026-08-10:**
  - `SessionsHermesClient+RunsTransport.swift:190` —
    `.toolCompleted(name: toolName, error: payload["error"] as? String)` —
    `as? String` on a Bool → `nil`.
  - `:288` — the stored-hop struct does the same
    (`self.error = payload["error"] as? String`).
  - `:524-541` — the consumer already carries the #296 plumbing (comment block
    at `:525-535` documents the C1 intent); it receives `nil` today, so the
    chip resolves `.completed` with `failure == nil`.
- **User-visible, observed twice:** the wire probe, then LIVE during #304's
  deny arm (2026-08-09 evening, build 2418) — a DENIED `rm -rf` rendered as a
  clean ✓ TERMINAL chip while a STOPPED tool showed an honest orange
  "Stopped" (client-local knowledge, 296-A). The deny's dishonest-clean chip
  is exactly this parser drop. #180's honest-degradation family.
- **Also owed from the lane's close-out (NEEDS-OWEN, small approvals): the
  3-line mapping test** — parser and consumer are each pinned, but the
  one-line mapping BETWEEN them is not (it lived outside the lane's allowlist).
  This lane closes that gap.

## 2. Fix shape

Parse the union: `error` may be **Bool or String**. Bool `true` → a failure
with a generic detail ("the host reported an error" — no fabricated text);
String → carry it verbatim (the existing path); absent/`false`/unknown type →
no failure (today's behaviour). Apply at BOTH sites (`:190`, `:288`), ~~then
re-land the ChatStore write that 296-C1 reverted (see #296's entry, "the
`ChatStore` write reverted" block) so the failure reaches the chip.~~

> **🔴 CORRECTION 2026-08-10, from the executing lane — the struck clause is
> FALSE, and there is nothing to re-land.** This brief misread #296's entry.
> The block it cites, *"296-C1, the `ChatStore` write reverted"*, sits under
> that entry's **"The RED steps, and what each failed ON"** heading: it records
> a write reverted *temporarily, to witness a RED*, and restored inside the same
> commit. It is not a record of a standing revert.
>
> **Verified at HEAD (`d004c82`):** the write is live at
> `Talaria/Stores/ChatStore.swift:749-751` —
> `if let failure = event.detail, !failure.isEmpty { conv.messages[idx]
> .toolActivities[last].failure = failure }` — and
> `git show 31563f6 -- Talaria/Stores/ChatStore.swift` shows the #296 fix commit
> ADDING it, never removing it.
>
> **So the chain's only broken link is the two `as? String` reads.** Once the
> union parse lands at `:190`, the existing transport mapping and the existing
> ChatStore write carry the failure to the chip untouched. A lane that
> "re-lands" the write would be re-adding code that is already there — and
> would likely duplicate it.

## 3. Bars — copy into #296's entry before the run

- **C1-A (RED→GREEN):** a `tool.completed` frame with `error: true` (Boolean —
  the fixture matches the wire capture byte-shape) yields a chip with
  `failure != nil`, rendered failed, not ✓. RED first on unmodified HEAD.
- **C1-B:** a String `error` still carries its text verbatim
  (`RunsFrameParserTests.toolCompletedCarriesTheHostError` stays green).
- **C1-C:** the no-key and `error: false` cases stay clean-✓
  (no-regression on honest completions).
- **C1-D (the mapping test):** the parser→consumer handoff is pinned
  end-to-end — a parsed failure lands on the chip's `failure` through the real
  `ChatStore` path, not via each half's own mock.
- **C1-E:** legacy decode — a pre-#296 persisted blob (no `failure` key)
  still round-trips (`legacyToolActivityJSONStillDecodes` stays green).
- **C1-F:** `GATE: PASS`, counts MOVED.

## 4. Traps

- **Do not invent error text for the Bool case.** The wire carries no message;
  the chip says "failed," not a fabricated reason. Real-data-only rule.
- The STOPPED path (296-A, client-local) is correct and separate — don't
  unify it with this; a stop is not a host error.
- The deny arm's BLOCKED prose arrives as ordinary content — this lane touches
  only the tool-chip channel.
- 296-C2's device row is ANSWERED (device list R5, wire probe) — do not
  re-queue it.

## 5. Owen's to decide

Nothing — the fix implements what the wire already proved. If the host is ever
observed sending a String on this field too, C1-B already covers it.

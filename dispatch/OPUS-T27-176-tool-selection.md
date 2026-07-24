# OPUS-T27-176 — the on-device tool belt is too eager

**Item:** OPEN_ITEMS #176 (touches #61, #28) · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-176-tool-selection` · **Toolchain:** Xcode-beta4, pinned sim
**Baseline:** 1121 tests / 103 suites + 8 UI · `export GH_PAGER=cat` first

## The observation

Standalone, ON-DEVICE model, whoGoesThere, build `cbcc824`. Prompt: **"Write a haiku about rain."**
The turn fired **`readImageText`** — an OCR tool — with no image anywhere in the conversation and
nothing to read. The reply then opened *"I can't create a haiku directly, but here's a simple one:"*
and produced a haiku anyway.

Earlier the same session, "Hello. How are things working today?" fired **4 tool calls** returning
health and motion. Appropriate there — but together they show a tool belt that reaches by default.

**Not yet investigated. This is a confirm-then-fix lane, not a known-change lane.**

## Two defects, and they must be separated

1. **The spurious INVOCATION.** A vision tool selected for a text-only prompt with no image in
   context.
2. **The refusal preamble.** "I can't create a haiku directly" reads like the model narrating a
   tool result it should never have had — then contradicting itself by producing the haiku.

**(2) may be downstream of (1) or independent.** Establish which before fixing either. If the
preamble persists once the spurious call is gone, it is its own item — file it, do not widen this
lane to chase it.

## Why it matters more than a wasted call

Every spurious call costs latency and context on a small on-device model — that turn measured
**IN 3.5K / OUT 65 / 4.9s**.

And it compounds: **#61's card generation consumes the reply**, so a tool-narrating preamble
becomes the conversation's *title*. The haiku turn is the exact device case #61's exact-prefix
guard was built against. **These two items met on one turn**, which is why this is worth a lane
rather than a shrug.

## Scope

**Phase 1 — confirm.** Find the on-device tool-belt definitions and the selection prompt. Establish:
- What `readImageText`'s description says, and whether it advertises an applicability condition at
  all ("use ONLY when an image is present in the conversation")
- Whether tool availability is **gated on context** — is `readImageText` even offered when no image
  is attached? Gating it out entirely may be the whole fix and is stronger than prompt-tuning.
- Whether the selection prompt tells the model it may answer with **no tool**. Belts that list
  tools without an explicit none-of-these path bias toward reaching.
- Whether the device tool belt differs from the connected-tier belt, and how.

**Phase 2 — fix the narrowest thing that works.** Preference order:
1. **Availability gating** — do not offer a vision tool with no image in context. Structural; the
   model cannot pick what it is not given.
2. **Tool description tightening** — explicit applicability conditions.
3. **Selection-prompt change** — last resort, hardest to test, easiest to regress.

**Do not rewrite the tool belt.** The 4-call health/motion turn was *appropriate*; the belt is not
broken, it is under-conditioned. A lane that comes back having redesigned tool selection has
overshot.

## Tests

The model's choice is not deterministic and **must not be asserted on**. Test what is deterministic:

- If gating lands: given a context with no image, `readImageText` is **absent** from the offered
  tool set; given an attachment, it is present.
- If descriptions change: the belt still serializes correctly and every tool retains its schema.

**Do not write a test that sends a prompt and asserts the model did not call a tool.** That test
passes and fails on model temperament, which is #183's masked-test pattern arriving by a new road.

## Verification

Full suite on the pinned sim `47F68496-24F9-45D9-93D3-1C778DB6B557`, `CODE_SIGNING_ALLOWED=NO`;
report against **1121 / 103**, account for the delta. `xcodegen generate` only if Swift files are
added or removed.

**Device verification is Owen's and is owed:** the literal prompt "Write a haiku about rain" on the
on-device model, standalone, confirming no `readImageText` call and no refusal preamble. State it
as owed, not done — this cannot be verified on sim, where the on-device model path differs.

## Commit discipline

File-scoped commits. OPEN_ITEMS.md separate. `gh pr merge --merge`, never squash.

## Out of scope

#61's card generation (its exact-prefix guard already shipped in PR #143). The connected-tier tool
belt unless the confirm shows they share a definition. `DeviceHealthTool` behaviour (#28) — the
health/motion calls were appropriate.

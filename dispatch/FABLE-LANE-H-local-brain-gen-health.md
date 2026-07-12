# FABLE LANE H — Local brain generation health (#102, #61)

**OPEN_ITEMS:** #102 (phrase-loop + thermal), #61 (degenerate title/preview)
**Branch prefix:** `claude/t27-lane-h-`
**Collision:** touches `LocalChatBackend.swift` + `LocalIntelligenceService.swift`
only. No ChatScreen/composer/drawer contact. Independent of Lanes D/F/G.

## Findings (source-read 2026-07-11 — treat as hypotheses to verify)

1. `LocalChatBackend.swift:597` — `respond`/stream uses bare
   `GenerationOptions()`: default sampling, NO `maximumResponseTokens`. A
   repetition loop generates until the context fills → sustained ANE burn →
   observed thermal state "serious" with only Talaria running (#102).
2. `LocalIntelligenceService.swift:74/114/173` — guided generation at
   temperature 0.2–0.3. Near-greedy sampling on the small on-device model is
   repetition-prone; #61's device symptom (title and preview showing the same
   repeated text) is consistent. NOT yet log-confirmed whether the generated
   path or the guardrail fallback produced it — the fix below protects both
   paths unconditionally, so confirmation is not a blocker.

## Probe-first (before coding)

- Verify the exact `GenerationOptions` API surface against the iOS 27 beta SDK
  (Apple docs JSON, same method as #61's 2026-07-06 verification): property
  names for max tokens (`maximumResponseTokens`?) and sampling mode. Do not
  code from memory.
- Read the existing tests for both files and extend, don't fork, their style.

## Deliverables

### 1. Bound + retune chat generation (#102)
- `LocalChatBackend`: replace bare `GenerationOptions()` with an explicit
  config — a sane `maximumResponseTokens` cap for chat replies (proposal:
  1024; justify in the PR if you pick differently) and a moderate temperature
  (~0.7) or the SDK's recommended sampling mode for conversational output.
- Tail-repetition breaker on the streaming loop: if the accumulated tail
  repeats the same run N times (cheap suffix check on `latestFull` each
  snapshot), stop consuming the stream, keep what's emitted, and log via the
  existing Logger. Conservative thresholds — never trip on legitimate
  repetition (lists, code).

### 2. Degenerate-card guard (#61)
- `LocalIntelligenceService.conversationCard`: after generation, validate the
  result — if title and preview are near-identical (case/whitespace-folded
  containment) OR either shows tail repetition, discard and return
  `fallbackCard` (known-good shape). Log which guard tripped so the device
  log finally tells us which path misbehaves.
- Nudge card temperatures up modestly (0.2→0.5 range) ONLY if tests show the
  guard tripping often at current temps; otherwise leave and let the guard
  carry it.

### 3. Tests
- Swift Testing: streamDelta/tail-repetition unit coverage (trips on looped
  phrase, does NOT trip on lists/code), card guard (identical, containment,
  repetition, and healthy cases pass through), options config presence.

## Constraints & acceptance
- No other files. File-scoped commits; no pbxproj (no new files expected —
  if tests need a new file, pbxproj regen rides its own commit).
- All suites green (Swift Testing pass line). PR titled
  `Lane H — local brain generation health (#102 #61)`.
- Device re-verify (Owen): phrase-loop gone or self-terminating, thermal
  recovers, titles/previews distinct — and the new guard logs identify the
  #61 path if it still trips.

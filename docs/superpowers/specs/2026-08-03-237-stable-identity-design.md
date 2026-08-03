# #237 — stable message identity, reconcile idempotence, and the dedupe sweep (design)

**Date:** 2026-08-03 (afternoon) · **OPEN_ITEMS #237** · Routed by Owen ("merge
and go") on the design recorded in the entry; root cause found by read-only
investigation the same hour.

## Root cause (evidence-complete, in the entry)

The "unconfirmed locals" preserve at the end of `mergeConversationMetadata`
(ChatStore ~2076–2081) keeps any local message the refreshed transcript doesn't
contain **by UUID or `clientMessageID`**. Server-adopted rows from a previous
adoption have neither — `mapStoredMessage` mints fresh UUIDs per fetch — so
every later reconcile/adoption appends the entire prior transcript as
"unconfirmed." Owen's plex thread: 32 → 128 in two resolutions (the double
resolution itself came from a late `.interrupted` re-arming a second
PendingRun). Reopen runs the same merge, so nothing self-heals.

## The fix — three surgical parts

### F1: stable identity at the mapping boundary

`mapStoredMessage` gains the session id and derives the Message id
deterministically when the server row has an id:

- New pure helper `SessionsHermesClient.stableMessageID(sessionId: String,
  serverRowID: Int) -> UUID` — SHA-256 over `"talaria-msg:\(sessionId):\(serverRowID)"`,
  truncated to 16 bytes with RFC-4122 version/variant bits set (a v5-style
  deterministic UUID; CryptoKit, no new deps).
- Rows lacking a server id keep the fresh-UUID fallback (rare, honest).
- Consequence: a re-fetch reproduces the same ids → the preserve filter's
  `refreshedIDs.contains(local.id)` recognizes previously-adopted rows → the
  append shrinks to genuinely-unconfirmed locals (in-flight sends), its
  designed purpose.

### F2: run-resolution idempotence

`ChatStore` keeps an in-memory `resolvedRunIDs: Set<String>` (conversation
lifetime, cleared with the thread):

- `attemptReconcile` records `pending.runId` (when non-nil) on successful
  resolution.
- The `.interrupted` handler ignores a late interrupt whose `runId` is already
  in the set (no second PendingRun, no second adoption, no second notify).
  A nil `runId` keeps today's behavior — idempotence keys on real run ids only.

### F3: the dedupe sweep (clean existing corruption)

Pure static `Conversation.dedupingAdoptedEchoes(_ messages: [Message]) ->
[Message]`: first occurrence wins for messages sharing the triple
(`sender`, trimmed `content`, `timestamp`) — with empty-content rows deduped
only when their `toolActivities` labels also match (tool-shell rows). Applied
in two places: on cache restore and after merge adoption. Idempotent by
construction; a legitimately re-sent user message differs in timestamp and
survives. This heals Owen's 4× plex thread on first load under the fix build.

Honest limits, recorded: the triple heuristic could collapse a true duplicate
sent within the same timestamp second — accepted (server timestamps are
sub-second floats; collision requires identical content in the same instant).

## Bars (mirrored into the entry before the lane runs)

- **237-A (sim):** `stableMessageID` is deterministic across calls and distinct
  across rows/sessions; two decodes of the same fixture produce identical id
  sequences; a rowless message still gets a unique id.
- **237-B (sim):** two successive adoptions of the same server transcript leave
  the message count UNCHANGED (no growth), while a genuinely-unconfirmed local
  send still survives the merge — the preserve's designed purpose pinned.
- **237-C (sim):** a second `.interrupted` carrying an already-resolved runId
  produces no second adoption and no second `onRunResolved` (count == 1).
- **237-D (sim):** the sweep collapses a synthetically quadrupled thread to
  single copies, is idempotent, and preserves distinct-timestamp repeats.
- **237-E (device, Owen):** the plex thread renders single copies under the fix
  build (sweep heals 128 → one set), and the parked 235-F bar becomes
  runnable: a staged recovery produces ONE marked reply and no thread growth.

## Testing

TDD, RED watched; tests ride `AppStoresTests` (merge/reconcile fixtures exist)
and `ReasoningChannelTests`/client-side for the id derivation. Gate before PR;
OTA carries 237-E + the parked 235-F device bar.

# FABLE T27-123 — Share extension: send anything into a Hermes session

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-123-*`
**Dispatch date:** 2026-07-17 · **Tracks:** OPEN_ITEMS #123 (new) · **Size:** one PR, medium-large
**Baseline:** 755/62 · **Toolchain:** Xcode-beta3.

## Why

Agent-files ships content OUT of sessions (#21). Inbound share is the missing
half and the habit-forming one: share a URL, PDF, image, or text from any app
→ it lands in Talaria's composer as a pending attachment. Free-tier feature
(works with the on-device brain too) — it feeds the funnel.

## The build

1. **New target `TalariaShare`** in `project.yml` — mirror the
   `TalariaWidgets` target as the pattern (verified at project.yml:319):
   extension point `com.apple.share-services`, bundle id
   `org.aethyrion.talaria27.share`, app group `group.org.aethyrion.talaria`
   (same as widgets, project.yml:63/:336). **NSExtensionActivationRule:
   support url (1), image (up to 4), pdf/file-url (1), plain text — use a
   TRUEPREDICATE-free dictionary rule; App Review rejects TRUEPREDICATE.**
2. Extension UI: minimal SwiftUI sheet — item preview + optional note field +
   "Send to Talaria". NO network calls in the extension (memory + review
   constraints): serialize the payload into the app group container
   (`SharedInbox/` dir, one JSON envelope + attachment blobs, size-capped
   ~20MB) and complete the request.
3. App side: on foreground/scene-activate, drain `SharedInbox/` → convert to
   the EXISTING `PendingAttachment` model (verified present:
   `Talaria/Models/PendingAttachment.swift`) + prefill composer text; deep
   route to the chat composer. Multiple queued shares → process in order.
   Corrupt/oversize envelope → skip + log, never crash the drain (tolerant,
   house rule).
4. Entitlements: the share target needs the app group in its OWN entitlements
   file — model on `TalariaWidgets`' arrangement; the regen/entitlement
   verification rule applies to BOTH targets now (check the main app's
   `aps-environment` AND the new target's app group survive every regen).

## Tests

Envelope encode/decode round-trip; drain: order, dedupe, corrupt-skip,
size-cap; activation-rule plist literal pinned by a config test (so a regen
or edit can't silently drop a type).

## Constraints & acceptance

- **This lane adds a TARGET — the regen is substantial.** pbxproj regen commit
  separate; verify both targets' entitlements post-regen; new target must not
  disturb the widgets or test targets (diff the pbxproj regen for scope).
- No network, no HealthKit, no location in the extension. Suite green ≥
  755/62 plus new tests.
- Device check for Owen (PR body): share a URL from Safari, a photo from
  Photos, a PDF from Files → each lands in the composer; two rapid shares
  queue correctly; a 25MB video is refused politely in the sheet.

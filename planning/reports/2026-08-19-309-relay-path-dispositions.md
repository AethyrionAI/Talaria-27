# #309 — the 16 surviving relay paths, with adapt-or-delete dispositions

> **✅ ANSWERED 2026-08-19, the same day, ahead of the scheduled review.**
> Owen ruled all three questions at the foot of this report: **(1) voice
> re-homes onto the PLUGIN** — route (b), a phone-held provider key, is
> rejected — now filed as **#383**; **(2) path 16's personalities and quick
> commands are an ACCEPTED LOSS**; **(3) #310 opens AFTER #368.** The table
> below is accepted as written — no row flipped. Read §"Questions for Owen"
> as the record of what was asked, not as anything still outstanding.

**Written 2026-08-19 AM for Owen's Thursday review.** Every path below was
re-grepped at HEAD `f48add84` this morning; the call sites are line-cited so
the table can be checked rather than believed. Nothing here is a fix, a
build, or a relay change — this is the disposition exercise #309 was filed
to produce, and the no-hardening rule (Owen, standing, 2026-08-02) applies
throughout.

**The direction is already ruled** (Owen, 2026-08-18 ~23:05, recorded in
#309): *"The smarter thing to do would be to adapt to the new runs interface
and tools we have available with the plugin instead of falling back to old
processes."* So the only two dispositions available are **ADAPT** (runs
interface / talaria plugin / gateway route) and **DELETE**. A restored relay
is a migration bridge, never a destination — which is why "keep it on the
relay" is absent from the table as a category, not merely unused.

~~**What Thursday's ruling is actually for:** the table's four ADAPT rows and
the two design questions inside them.~~ **Both design questions were ruled
on 2026-08-19 (see the banner). What remains is lane work, not decisions:**
the twelve DELETE rows are mechanical once #310 lands, paths 7 and 16 are
plain re-points, and paths 11–12 are #383.

---

## The table

| # | path | call site (HEAD) | disposition | notes |
|---|---|---|---|---|
| 1 | `POST device/register` | `LiveSessionBootstrapService.swift:110` | **DELETE** | The relay identity the gateway plane does not use. |
| 2 | `GET session` | `LiveSessionBootstrapService.swift:132` | **DELETE** | Same chain as 1. |
| 3 | `POST auth/refresh` | `LiveSessionBootstrapService.swift:150` | **DELETE** | Same chain as 1. |
| 4 | `POST auth/revoke` | `LiveSessionBootstrapService.swift:163` | **DELETE** | Same chain as 1. |
| 5 | `POST device/provisioning` | `AppContainer.swift:826` (`ProvisioningService`) | **DELETE** | **Already named**: #375's one remaining scope is exactly this file's deletion. Free. |
| 6 | `POST phone-pairing/redeem` | `LivePairingService.swift:62` | **DELETE** | The gateway key *is* the pairing under #251/#269. |
| 7 | `GET hosts/current` | `LiveHermesHostService.swift:45` | **ADAPT → gateway `/health`** | The app already probes this fact twice by other means. |
| 8 | `POST hosts/enrollment-codes` | `LiveHermesHostService.swift:56` | **DELETE** | Enrollment dissolves with 6. |
| 9 | `POST hosts/current/revoke` | `LiveHermesHostService.swift:71` | **DELETE** | Unpair becomes "forget the key", local. |
| 10 | `POST device/app-state` | `AppContainer.swift:1969` | **DELETE** | Fire-and-forget beacon nothing app-side reads. |
| 11 | `GET talk/readiness` | `LiveVoiceSessionService.swift:192` | **ADAPT → plugin (#383)** | 🔴 The one genuine build in this table. Route ruled 2026-08-19. |
| 12 | `POST talk/session` | `LiveVoiceSessionService.swift:278` | **ADAPT → plugin (#383)** | 🔴 With 11. |
| 13 | `GET conversations/current` | `LiveHermesClient.swift:104, 234, 423` | **DELETE** | ⚠️ Already dead in production — see below. |
| 14 | `POST messages` | `LiveHermesClient.swift:128, 165` | **DELETE** | ⚠️ Already dead in production. |
| 15 | `POST conversations/current/clear` | `LiveHermesClient.swift:260` | **DELETE** | ⚠️ Already dead in production. |
| 16 | `GET commands` | `AppContainer.swift:1845` | **ADAPT → gateway `/v1/skills`** | Skills only — personalities + quick commands are a RULED accepted loss (2026-08-19), not a gap to fix later. |

**Counts: 12 DELETE · 4 ADAPT.** Of the twelve deletes, **three are already
unreachable in the shipped app** and **one is already scoped for deletion by
another item**, so the true remaining delete work is eight paths across four
files.

---

## The three findings this pass produced

### 1. `LiveHermesClient` is dead production code (paths 13–15)

`LiveHermesClient` is **never constructed anywhere in `Talaria/`**. Its only
references in the whole repo are three fixtures in
`TalariaTests/AppStoresTests.swift:2679, 2736, 3428`. The shipped chat client
is `SessionsHermesClient` behind `ChatBackendRouter`; the relay-era
conversation feed it implements has no live caller.

So three of the sixteen paths cost nothing to remove but the class and those
three test fixtures. **Verify before acting** — this is a grep at one HEAD,
and a lane must re-check rather than inherit the claim (the #279/#184 shape:
a premise read from a header rather than from code).

### 2. Voice is the only path that needs a new home built (11–12)

Owen's direction rules out the relay as voice's destination, and the entry
already records that `POST /api/platforms/talaria/events` **does not
currently carry voice**. So this is not a re-point; it is a design.

Two candidate homes, neither designed:

- **(a) The plugin gains a voice-session route** reached over the talaria
  platform link — the app asks the host to mint a realtime session, exactly
  as `talk/session` does today, and the provider key stays host-side.
- **(b) The app mints the realtime session directly** against the provider
  with a key held on the phone; the host leaves the loop entirely.

**Recommendation: (a).** It preserves the one property the relay was actually
buying — the realtime key never reaching the device — and the realtime key is
now present on **both** hosts (#254-D/#303), which is what makes it
buildable at all. (b) is smaller but moves a provider credential onto the
phone, which is a security posture change Owen has never been asked for.

This deserves its own tracker number the day it is routed (#268), not a
sub-bullet of #309.

### 3. The auth chain is not merely legacy — it is on the blocking UI path

Paths 1–4 run from `AppSessionStore.bootstrap()`, and **`bootstrap()` is
awaited inside `AppContainer.handleActiveProfileChanged`** — which is the
mechanism behind **#365** (diagnosed the same morning; see that entry). Both
hosts' relays are now retired, so every one of those calls is a doomed round
trip, and the recovery ladder inside `bootstrap()` adds two more before
giving up.

**Consequence for sequencing:** the auth-chain deletes are not cosmetic
tidying that can wait for Phase 4. They are currently costing a
user-visible, full-screen stall on every profile switch. #365's own fix
(suppressing the splash) treats the symptom; deleting paths 1–4 removes the
cause.

---

## What blocks the deletes

- **#310** (`BackendProfile.relayBaseURL` is non-optional) gates 1–4, 6, 8, 9:
  until a profile can exist without a relay URL, the app cannot express the
  end state these deletions produce. #310 is the first move, exactly as its
  entry says.
- **#375's remaining scope** already owns path 5 and can take it this week
  with no ruling.
- **Paths 13–15** are blocked by nothing but a lane.
- **Path 7** needs a small decision (does `hostStore` read `/health` or
  `/health/detailed`?) — not a ruling, a lane's judgement.
- **Path 16** carried the one non-voice open question — `/v1/skills` covers
  the skills half, but **personalities and quick commands have no named
  gateway source**. **RULED 2026-08-19: accepted loss.** Nothing blocks this
  row now; the lane that adapts it must make the omission degrade honestly
  (#180) rather than render an empty section.

---

## Questions for Owen — ALL THREE ANSWERED 2026-08-19

1. **Voice's new home — (a) plugin route, or (b) phone-held provider key?**
   Recommendation was **(a)**; (b) puts a provider credential on the device.
   → **RULED (a), the plugin route. Filed as #383**, where the rejection of
   (b) is recorded as a standing constraint rather than a preference — so a
   later lane cannot reach for it as a shortcut when the plugin work proves
   bigger than expected.
2. **Path 16's non-skill halves — build a gateway source for personalities
   and quick commands, or accept the loss?** Recommendation was **accept the
   loss for v1**.
   → **RULED: accept the loss.** After the adapt the catalog is
   skills-plus-local. **The two missing halves are a ruled omission, not a
   regression** — and whatever surfaces them must degrade honestly (#180)
   rather than render an empty section. Recorded at #309 so a later session
   does not read the gap as a defect and "fix" it.
3. **Sequencing:** #310 now, or after #368's cutover? Recommendation was
   **after #368**.
   → **RULED: after #368**, trigger = that merge. Recorded at #310, together
   with the note that #365 upgraded #310 from an onboarding blocker to the
   unblock for a live, every-profile-switch UI stall.

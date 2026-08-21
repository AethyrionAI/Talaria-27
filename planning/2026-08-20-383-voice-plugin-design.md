# #383 — re-homing the realtime voice bootstrap onto the talaria plugin

**Design pass, 2026-08-20.** No code, no bars yet — #383's entry says bars
pre-register only after the shape is chosen, and the shape is what this
document proposes. **The plugin half needs Owen's per-experiment live-install
go before anything deploys; nothing here has been deployed or modified.**

Route **(a) — the plugin route — was ruled 2026-08-19**. Route (b), a
phone-held provider key, is rejected and stays rejected: it moves a provider
credential onto the device, a security posture change nobody asked for. Do not
reach for it when the plugin work proves bigger than expected — raise it with
Owen as a decision instead.

---

## 1. What actually moves — FOUR paths, not two

#309's table and #383's own opening list two. There are four, and the two
missing ones were found by grepping the CALL SHAPE rather than the path text
(they are interpolated, so a literal grep structurally cannot see them):

| # | path | site | what it does |
|---|---|---|---|
| 11 | `GET talk/readiness` | `LiveVoiceSessionService.swift:192` | may a realtime session start? |
| 12 | `POST talk/session` | `:278` | mint one |
| — | `POST talk/session/{id}/end` | `:708` | release it |
| — | `POST talk/session/{id}/turns` | `:729` | persist a turn |

**They cannot be dispositioned separately.** A minted session that cannot be
ended leaks host-side; a turn that cannot be persisted silently drops
transcript — which is #173's silent-degradation family, in the voice plane.

## 2. The contract to reproduce

From `LiveVoiceSessionService.swift:32-57`, `POST talk/session` returns:

```
{ voiceSession: { id, status, model, voice, startedAt, endedAt, lastError },
  bootstrap:    { clientSecret, expiresAt, session: { id }, model, voice } }
```

**`bootstrap.clientSecret` is the whole point.** It is an EPHEMERAL realtime
credential minted host-side. That is the one property the relay was actually
buying, and the reason (b) was rejected. **A design that cannot mint a
short-lived secret has not solved this item**, and handing over the long-lived
key is the rejected route wearing a different hat.

`GET talk/readiness` returns `hostOnline / configured / ready / selectedModel /
voice / voiceContextUpdatedAt`, which feed `TalkReadinessInfo`'s tri-state
optionals (nil = unknown, and #180 requires that nil stay distinguishable from
false).

## 3. The transport already exists — this is VERBS, not routes

The decisive architectural fact, and the reason this is smaller than it looks:

**`TalariaPlatformLink` speaks ONE endpoint** — `POST /api/platforms/talaria/events`
(`TalariaPlatformLink.swift:31`) — **with the verb in the body.** Host-side,
`envelope.py:113-119` dispatches from a plain dict:

```python
handler = {
    "pair": self._pair,
    "drain": self._drain,
    "ack": self._ack,
    "query_result": self._query_result,
    "unpair": self._unpair,
}.get(event_type)
```

So the plugin half is **four new entries in that dict plus their handlers**.
No new route, no new auth surface, no gateway change, nothing that
`hermes update` can overwrite (the plugin lives in `~/.hermes/plugins/talaria`,
outside `hermes-agent`).

**Proposed verbs**, named to match the existing noun.verb shape:

| verb | replaces | returns |
|---|---|---|
| `talk_readiness` | `GET talk/readiness` | the readiness fields |
| `talk_session_create` | `POST talk/session` | `voiceSession` + `bootstrap` |
| `talk_session_end` | `POST talk/session/{id}/end` | ack |
| `talk_turn_append` | `POST talk/session/{id}/turns` | ack |

## 4. Feasibility — CONFIRMED, not assumed

The plugin runs in the gateway process, and **`OPENAI_API_KEY` is present in
`~/.hermes/.env`** (verified 2026-08-20, read-only). So the handler can mint an
ephemeral secret against the provider with a key that never leaves the host —
exactly what the relay did. #254-D/#303 record the realtime key on **both**
hosts, which is what makes this buildable on OJAMD too rather than only here.

## 5. What gets SIMPLER, and it is worth saying out loud

Voice currently authenticates with **relay access tokens** — the #15/#94
refresh-and-recover ladder, a second credential family with its own expiry.
On the plugin it authenticates with the **device token** minted by `pair`,
which the app already holds and already re-pairs on 401
(`TalariaPlatformLink.drain`, one re-pair then give up).

**Voice stops being a second auth plane.** That is a real reduction, not a
lateral move, and it is the strongest argument for (a) beyond the security one.

## 6. The hazards, named before anyone builds

1. **🔴 `TalariaPlatformLink` is foreground-only and epoch-superseded (#285).**
   `stop()` bumps the turn epoch and in-flight work abandons at its next
   checkpoint. A voice bootstrap abandoned mid-flight would leave a **minted
   host-side session with no client** — the #288 orphan-row shape, but holding
   a provider session. Voice verbs must either be exempt from supersession or
   carry a compensating `talk_session_end`. **This is the one part of the
   design that is genuinely new risk**, and it is where bars should be
   hardest.
2. **The drain loop long-polls with `wait: true` (up to 40 s).** Voice
   bootstrap is latency-critical; it must not queue behind a held drain. The
   verbs need their own request, not a slot in the drain turn.
3. **Latency budget.** Today `configureAudioSession()` and WebRTC preparation
   run in PARALLEL with the relay bootstrap, deliberately saving ~200–500 ms
   (`:265-272`). The envelope hop must preserve that parallelism or the
   regression will be audible as a slower start.
4. **`#138` (realtime self-barge-in) and `#303` (the engine-pin race) both
   live on this path.** Neither may regress, and #303's cold-launch arm reads
   a realtime *permission* — so it has a direct interest in whatever replaces
   `talk/readiness`.
5. **Two hosts, one plugin version.** OJAMD and the Mac must run the same
   plugin build or the app faces a host that knows `talk_session_create` and
   one that returns `unknown_event_type`. The app should degrade honestly on
   that error rather than hang (#180), which is itself a bar.

## 7. Sequencing proposal

1. **Plugin half first, behind its own verbs.** Additive — the existing five
   verbs are untouched, so a half-deployed plugin still serves chat and
   sensors normally.
2. **App half second**, swapping `LiveVoiceSessionService`'s `RelayAPIClient`
   for the platform link. The service's shape barely changes: same four calls,
   same decode targets, different transport.
3. **Delete the relay paths third**, with #309's rows 11–12 (plus the two this
   pass adds).

Each step is independently revertable, and step 1 deploys nothing user-visible.

## 8. Questions for Owen

1. **Supersession (hazard 1) — exempt the voice verbs, or compensate?** Exempt
   is simpler and risks a stuck session on a genuine stop; compensate is
   correct and adds a cleanup path that itself can fail. **Recommendation:
   compensate**, because a leaked provider session costs money and the cleanup
   failure mode is bounded by the session's own expiry.
2. **Does `talk_turn_append` survive at all?** It persists voice turns
   host-side. #1's `postVoiceTranscriptsToHermes` already posts transcripts as
   normal text turns on the Sessions API — so this may be a **second** path to
   the same end, and the honest answer might be to drop it rather than port
   it. **Recommendation: investigate before porting**; if it duplicates #1,
   accept the loss like #309 path 16.
3. **Live-install go** for deploying the plugin half to the Mac first, then
   OJAMD. Not requested yet — this document is the design, and nothing
   deploys until you grant it in your own words.

## 9. What this design does NOT do

It does not touch the relay, restart it, or depend on it. Per Owen's standing
direction (2026-08-18): a restored relay is a migration bridge, never a home,
and a capability gap is adapted forward rather than fallen back.

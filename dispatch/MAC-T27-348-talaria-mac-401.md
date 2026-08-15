# MAC T27-319 — a Talaria build on the Mac has never authenticated to OJAMD

**For:** Claude Code, next session, **on the Mac Mini** · **Tracks:** OPEN_ITEMS **#348** ·
**Written:** 2026-08-15, from a session running **on OJAMD itself** · **Branch:**
`t27-271-ojamd-phase5-317` ([PR #307](https://github.com/AethyrionAI/Talaria-27/pull/307))

**Read this first: the OJAMD half is already done.** Every host-side fact below was read live
from OJAMD's own access log by a session on that box — no `hermes-ojamd` MCP in the loop, so
the fabrication caveat does not apply. **Do not re-probe OJAMD for this**; you would be
re-deriving settled evidence from the wrong side of the wire. The unknown is entirely on your
end: *which Mac-side build is holding a bad credential, and why.*

---

## 1. What was found

OJAMD's gateway has been rejecting a Talaria build on the Mac Mini for at least five days.

```
2026-08-15 15:45:10 WARNING gateway.platforms.api_server: API server rejected invalid API key:
  remote='100.79.222.100' peer_ip='100.79.222.100' method='GET' path='/v1/models'
  user_agent='Talaria%2027/1 CFNetwork/3896.100.1.2.1 Darwin/25.5.0'
2026-08-15 15:45:10 INFO aiohttp.access: 100.79.222.100 ... "GET /v1/models HTTP/1.1" 401 599
```

Whole-log tally from `100.79.222.100`:

| Path | Status | Count |
|---|---|---|
| `/v1/models` | **401** | **85** |
| `/api/platforms/talaria/events` | 401 | 1 |
| `/api/sessions` | 401 | 1 |
| `/health` | 200 | 5 |
| `/api/sessions` + `/chat` | 200 / 201 | 11 |
| `/v1/toolsets` · `/v1/skills` · `/v1/capabilities` | 200 | 6 |

**Zero 200s on `/v1/models` from that IP in the entire log.** Today alone: 6 × 401, 0 × 200 —
the last pair at **16:00:53 / 16:01:07**, after the conversation that found it had already
started. The 401s arrive in **pairs ~14 s apart** (a client retry), at irregular intervals
across 2026-08-11 → 2026-08-15, plausibly on app foreground.

---

## 2. Already ruled out — do not spend the session re-testing these

| Hypothesis | Why it's dead |
|---|---|
| It's SSH being refused | It is HTTP to `:8642`, rejected by `gateway.platforms.api_server` for a **Bearer key**. Owen's "if it was ssh, that's expected — I don't allow it" does not apply. |
| OJAMD's key rotated / the host is misconfigured | **Other clients from the same IP authenticate fine in the same window** — `Python-urllib` on `/health`, plus a session-creating client running real chats. The expected key is valid and working. |
| It's the phone | `Darwin/25.5.0` is **macOS**. The paired iPhone reports `Darwin/27.0.0`. |
| #271 / today's work caused it | It predates that by four days and survived three gateway restarts, a plugin disable/enable cycle, and the `hermes_mobile` retirement unchanged. |
| It self-corrected on retry | It has **never once succeeded** on `/v1/models`. That was the first guess and the log refuted it. |

---

## 3. What to actually do, in order

**Step 1 — pin the build before theorising.** `Darwin/25.5.0` says something is running as
macOS, not iOS: Designed-for-iPad, Catalyst, or a sim whose UA is reporting the host. Find
which target is even running, and whether it is something you or a previous session launched
and left running. The retry pairs suggest a live process, not a one-off.

**Step 2 — determine EMPTY vs WRONG.** A 401 does not distinguish "the OJAMD profile was
created without a key" from "the key is stale." These have different fixes and different
stories about how they happened. Whatever store the app keeps profiles in is the source of
truth — read it, don't infer it from behaviour.

**Step 3 — explain `/v1/models` specifically.** That path is the model-catalog fetch. Two
readings, and the evidence leans to the second:
- *One call site is unwired* — the key reaches chat but not the catalog fetch. A **code** bug.
- *The credential is simply bad* — supported by the single `401 /api/platforms/talaria/events`,
  the plugin pairing endpoint, from the same build. That is a different call site failing the
  same way, which argues the credential is bad generally.

Settle it by finding whether that same build ever succeeded at anything against OJAMD.

**Step 4 — only if 1–3 leave something unexplained**, look at whether this composes with
**#285 / #288** (profile atomicity, orphan device rows). Nothing here proves a link; it is
adjacent, not implicated.

---

## 4. House rules that apply to this specific lane

- **Score from the host's log, never from a client's self-report.** This is **#347**, filed
  today after three "the tool is not available to me" replies turned out to be a model that
  never called `tool_search`. Same discipline here: the app's own diagnostics are a hypothesis;
  OJAMD's access log is the evidence — and it is quoted above so you do not need OJAMD to
  re-read it.
- **The Mac still runs its own shim** (`tools/models-shim/shim.py`, up since Jul 24, answering
  401 on `:8765`). That is a *different* 401 on a *different* port and is a known, harmless
  state — **do not conflate it with this item.** The shim is out of the model path entirely
  (#223 Lane 5); the app never calls it.
- **This is not a reason to touch OJAMD.** The production host is healthy and its half is
  closed. If the fix needs a new key on the Mac side, that is a Mac-side change.

---

## 5. State you are inheriting (as of 2026-08-15 16:00, all live-verified)

**OJAMD** — the phone's production host, and now materially simpler than the docs describe:

- `talaria` plugin **enabled, source git**, 2 active devices (iPhone + iPad).
- **`mcp_servers.hermes_mobile` disabled**; **zero** `hermes-mobile` processes on the box.
- Relay + shim services **Stopped + Disabled**; all three scheduled tasks **deleted**;
  `Hermes_Connector.cmd` removed from Startup. The gateway is the only piece still running.
- **OJAMD is on v0.20.1** (`165c889e5`), not the 0.20.0 the tracker assumed.
- `#271` closed with **every bar MET**, including 271-D and a live-exercised 271-J.

**Also routed to a Mac session, and adjacent to this one:**

- **#345** — the plugin health read. **Re-scope before spending a lane on it:** it did NOT
  reproduce on 2026-08-15 (real data came back — 197 steps, HR 72 bpm), so it is now a narrow
  "why are active-energy and sleep specifically empty" question, and the original 01:15 AM
  observation window is a stated confound.
- **#347** — the scoring rule above, plus its corollary that `devices.json`'s `last_seen` lags
  real drain contact by ~45 s and must not be used as a liveness gate.

**Repo:** branch `t27-271-ojamd-phase5-317`, PR #307 open, two commits (the lane + the S1–S6
close-out corrections to `CLAUDE.md`, the watchdog header, and the #271 dispatch). Pull before
starting so you inherit the corrected `CLAUDE.md` — several OJAMD sections in it were wrong
until today.

---

## 6. Definition of done

**#348 closes when the Mac build either authenticates or is shown to be something that should
not be running at all** — and the OJAMD access log stops accruing 401s from `100.79.222.100`.
That last clause is the actual bar: the host's log is the scoreboard, since the whole item was
found there and nowhere else.

**Impact is LOW — do not let it displace real work.** OJAMD rejects the requests cleanly,
nothing user-facing is degraded, and no phone behaviour is implicated. The costs are that the
build cannot read OJAMD's catalog, and that it has been quietly polluting the log everyone
greps while scoring device bars. It was filed because it is real and reproducible, not because
it is burning.

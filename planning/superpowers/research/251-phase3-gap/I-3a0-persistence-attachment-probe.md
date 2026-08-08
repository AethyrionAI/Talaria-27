# Report I — 3A-0 blocking probe: N4 (runs↔SessionDB) + N9 (attachment shape on `/v1/runs`)

**Run 2026-08-07, before any Phase 3 code, per the plan's own gate ("no code before both
answers are written down"). Read-only: live Mac gateway 0.20.0 (`~/.hermes/hermes-agent` @
`01a1037d1`, PID 19532, started 07:20 same day), no install modification, no config change,
no bounce. Auth = `API_SERVER_KEY` resolved by the probe script itself; the key never
entered the session transcript. Probe session: `api_1786118893_f3250a12` (junk rows left
in place per deactivate-never-delete). Consumers: plan §1.6 N4/N9 (dated ANSWERED notes),
tracker #283 (bars 3A-G / 3A-H), #251 dated note.**

The probe script (stdlib-only Python, reproducible against any gateway) is appended at the
end of this report verbatim.

## N4 — does a run carrying an existing `session_id` write into the row `/api/sessions/{id}/messages` reads?

**Answer: a SPLIT. Runs WRITE the row; runs never READ it.**

### Arm 1 — write (✓)

1. `POST /api/sessions` → `201`, id `api_1786118893_f3250a12`; `GET …/messages` → `[]`.
2. `POST /v1/runs {"input": "Reply with exactly the single word KUMQUAT-N4A …", "session_id": …}`
   → `202`, `run_ce5c0a77ceb14843a0b861a6f33f22bd`.
3. Terminal status: `completed`, `output: "KUMQUAT-N4A"`,
   `usage {input 31349, output 58, total 31407}`.
4. `GET …/messages` → **both rows present, verbatim** (ids 9565/9566): the user prompt and
   the assistant reply `KUMQUAT-N4A`, with the `reasoning`/`reasoning_content` columns
   populated.

Mechanism (code-read, why this is not luck): both planes share
`_create_agent(session_db=self._ensure_session_db(), session_id=…)`
(`api_server.py:2834`; runs call it at `:6451`, chat at `:6020`), and persistence lives in
the shared agent core — `run_conversation` → `agent/turn_finalizer.py:410`
`agent._persist_session` → `_flush_messages_to_session_db` (`run_agent.py:1889`). Nothing
in either HANDLER writes messages; it was always the agent.

**Consequence:** server-side history, `openSession`, fork, and the #190 local store
survive the migration unchanged. The plan §2.1 "stays" table holds.

### Arm 2 — read (✗)

`POST /v1/runs` on the SAME session: *"what exact marker word did I ask you to reply with
earlier in this conversation? If you have no record of it, reply exactly NO-HISTORY."*
→ `completed`, **`output: "BANANA"`**.

Not the marker, and not `NO-HISTORY` either: the reply came from the **long-term-memory
scope** — the agent's reasoning shows it consulting memory summaries of the 2026-08-06
steering probes (whose answer word was literally BANANA). Two lessons:

1. `_handle_runs` passes `conversation_history=[]` unless the request supplies it
   (`:6329-6360` — body or `previous_response_id` only; no DB load anywhere), where the
   chat plane loads DB history server-side (`_conversation_history_for_session`, `:3584`).
2. **A missing history does not fail loud — it hallucinates plausibly.** The long-term
   memory channel (S29) papers over the gap with confident, wrong continuity. This is why
   #283's bar 3A-G asserts the *marker content*, never mere non-emptiness.

### `previous_response_id` is not the fix

Only the `/v1/responses` handlers `put()` into the response store (`:4557`, `:5352`);
`_handle_runs` only ever reads it (`:6349`). **A completed run stores nothing**, so runs
cannot chain off each other. History supply options for slice 3A: (i) send the app-local
thread as `conversation_history`, or (ii) pre-fetch `GET …/messages` and build history from
server truth (kept current by the write half, including runs' own turns). Decided inside
the slice.

### Addendum (2026-08-07, review of #279) — a fresh, never-used session's first read

Slice 3A's runs turn driver GETs `/api/sessions/{id}/messages` before every submit (the
history pre-fetch decided above) — including a session's very first turn, right after
`POST /api/sessions` and before anything has ever been written to it. An independent
reviewer of PR #279 asked whether that pre-fetch 404s on a session nobody has used yet,
since `SessionsHermesClient.ensureSuccess` maps a 404 there to `SessionsClientError
.sessionNotFound` and could make a fresh install's very first turn fail before it ever
reaches `/v1/runs`. **Probed live and REFUTED just now:**

```
POST /api/sessions            -> 201 api_1786151818_f1050b82
GET  /api/sessions/{id}/messages on a NEVER-USED session -> 200 {"object":"list","session_id":"...","data":[]}
```

(Mac gateway, Hermes 0.20.0, 2026-08-07.) The same shape was already captured in this
report's own N4 Arm 1 step 1 above — `GET …/messages` → `[]` right after session creation
— but recorded too tersely there for a later reader asking this exact question to find it.

**So a freshly created, never-used session returns `200` with an empty `data` array, NOT
`404`.** The runs path's history pre-fetch is safe on a first turn by construction, and the
app needs no special-casing for it.

## N9 — does the app's attachment body survive `_handle_runs`'s input extraction?

**Answer: NO as-sent; YES with a message-array wrap.**

The app's attachment turns send `input` as a **content-parts array**
(`ChatTurnBody.make`, `SessionsHermesClient.swift:1698`):
`[{"type":"text","text":…},{"type":"image_url","image_url":{"url":"data:image/…"}}]`.

| arm | body | result |
|---|---|---|
| A1 | parts array, text part last-or-first (both orders tried) | **`400 "No user message found in input"`** — `_handle_runs` treats a list as a MESSAGE array and reads `raw_input[-1].get("content")` (`:6320`); no content part has a `content` key |
| B | `input: [{"role":"user","content":[<same parts>]}]` | `202` → `completed`, **`output: "Red"`** — the agent saw the 8×8 pure-red PNG fixture |
| control | same parts on `POST /api/sessions/{id}/chat` | `200`, `"Red"` (kimi-coding/kimi-k3) — fixture proven readable, so arm A's 400 is the shape, not the image |

Caveats carried to the slice:
- The runs path never calls `_normalize_multimodal_content` (`:550`) — parts reach the
  agent **unvalidated** (no data:image-only check, no size/count caps, no part-type
  rejection). The client keeps its own discipline; server-side rejection of bad parts
  cannot be relied on.
- Text-only turns are unaffected — plain-string `input` is exactly arm 1's shape.
- Multi-message `input` arrays also get their leading entries folded into history with
  part-flattening (`:6359-6369`) — an alternative history-supply channel to
  `conversation_history`, same precedence caveats.

## Probe script (verbatim)

```python
#!/usr/bin/env python3
"""3A-0 blocking probe (Phase 3 plan §3) — read-only, local Mac gateway.

N4: does POST /v1/runs carrying an existing session_id write its turn into
    the row GET /api/sessions/{id}/messages reads?  (+ history-READ arm:
    does a second run on the same session see the first run's content?)
N9: does the app's ChatTurnBody attachment shape (content-parts array)
    survive _handle_runs's input extraction? And does a message-array wrap
    of the same parts work instead?

No install modification, no config change. Agent turns are tiny one-word
prompts. Prints everything except the API key.
"""
import base64
import json
import os
import struct
import sys
import time
import urllib.error
import urllib.request
import zlib

BASE = "http://127.0.0.1:8642"


def load_key():
    candidates = []
    hh = os.environ.get("HERMES_HOME")
    if hh:
        candidates.append(os.path.join(hh, ".env"))
    candidates.append(os.path.expanduser("~/.hermes/.env"))
    for p in candidates:
        try:
            with open(p) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("API_SERVER_KEY="):
                        return line.split("=", 1)[1].strip().strip('"').strip("'")
        except OSError:
            continue
    return None


KEY = load_key()
if not KEY:
    print("FATAL: could not resolve API_SERVER_KEY from HERMES_HOME/.env or ~/.hermes/.env")
    sys.exit(1)


def req(method, path, body=None, timeout=30):
    r = urllib.request.Request(BASE + path, method=method)
    r.add_header("Authorization", "Bearer " + KEY)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r, data=data, timeout=timeout) as resp:
            raw = resp.read().decode()
            try:
                return resp.status, json.loads(raw) if raw else {}
            except json.JSONDecodeError:
                return resp.status, {"_raw": raw[:2000]}
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            return e.code, {"_raw": raw[:2000]}


def poll_run(run_id, budget=180):
    t0 = time.time()
    while time.time() - t0 < budget:
        st, body = req("GET", f"/v1/runs/{run_id}")
        status = body.get("status")
        if status in ("completed", "failed", "cancelled"):
            return st, body
        time.sleep(1.5)
    return None, {"_timeout": True}


def red_png_data_url():
    # 8x8 solid pure-red PNG, stdlib only.
    w = h = 8
    raw = b"".join(b"\x00" + b"\xff\x00\x00" * w for _ in range(h))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw))
           + chunk(b"IEND", b""))
    return "data:image/png;base64," + base64.b64encode(png).decode()


def section(title):
    print("\n" + "=" * 72)
    print(title)
    print("=" * 72)


# ---------------------------------------------------------------- sanity
section("SANITY: /health + auth")
st, body = req("GET", "/health")
print("health:", st, json.dumps(body))
st, body = req("GET", "/v1/models")
print("/v1/models auth check:", st, json.dumps(body)[:200])
if st != 200:
    print("FATAL: auth failed")
    sys.exit(1)

# ---------------------------------------------------------------- N4
section("N4 ARM 1 — run with session_id: does the turn persist into SessionDB?")
st, body = req("POST", "/api/sessions", {})
print("create session:", st, json.dumps(body)[:400])
sid = (body.get("session") or {}).get("id")
if not sid:
    print("FATAL: no session id")
    sys.exit(1)
print("session_id:", sid)

st, body = req("GET", f"/api/sessions/{sid}/messages")
print("messages BEFORE:", st, json.dumps(body)[:400])

marker = "KUMQUAT-N4A"
st, body = req("POST", "/v1/runs", {
    "input": f"Reply with exactly the single word {marker} and nothing else. Do not use any tools.",
    "session_id": sid,
})
print("POST /v1/runs:", st, json.dumps(body)[:400])
run_id = body.get("run_id") or body.get("id")
if not run_id:
    print("FATAL: no run_id")
    sys.exit(1)

st, body = poll_run(run_id)
print("terminal status:", st, json.dumps({k: body.get(k) for k in ("status", "output", "usage", "last_event", "error", "session_id")})[:600])

time.sleep(2)  # let any async flush land
st, body = req("GET", f"/api/sessions/{sid}/messages")
msgs = body.get("messages") or body.get("data") or body
print("messages AFTER run 1:", st, json.dumps(msgs)[:1500])

section("N4 ARM 2 — second run, same session_id: does the runs plane READ history?")
st, body = req("POST", "/v1/runs", {
    "input": ("Without using any tools: what exact marker word did I ask you to reply with "
              "earlier in this conversation? If you have no record of it, reply exactly NO-HISTORY."),
    "session_id": sid,
})
print("POST /v1/runs:", st, json.dumps(body)[:300])
run2 = body.get("run_id") or body.get("id")
if run2:
    st, body = poll_run(run2)
    print("terminal:", st, json.dumps({k: body.get(k) for k in ("status", "output", "error")})[:400])

time.sleep(2)
st, body = req("GET", f"/api/sessions/{sid}/messages")
msgs = body.get("messages") or body.get("data") or body
print("messages AFTER run 2:", st, json.dumps(msgs)[:2000])

# ---------------------------------------------------------------- N9
data_url = red_png_data_url()

section("N9 ARM A — the app's EXACT ChatTurnBody shape (content-parts array) on /v1/runs")
parts = [
    {"type": "text", "text": "What color is this image? Answer with exactly one word. No tools."},
    {"type": "image_url", "image_url": {"url": data_url}},
]
st, body = req("POST", "/v1/runs", {"input": parts, "session_id": sid})
print("parts-array (text first):", st, json.dumps(body)[:400])

st, body = req("POST", "/v1/runs", {"input": [parts[1], parts[0]], "session_id": sid})
print("parts-array (image first, text last):", st, json.dumps(body)[:400])

section("N9 ARM B — message-array wrap: input=[{role:user, content:[parts]}]")
st, body = req("POST", "/v1/runs", {
    "input": [{"role": "user", "content": parts}],
    "session_id": sid,
})
print("POST:", st, json.dumps(body)[:400])
run3 = body.get("run_id") or body.get("id")
if run3:
    st, body = poll_run(run3)
    print("terminal:", st, json.dumps({k: body.get(k) for k in ("status", "output", "error")})[:600])

section("N9 CONTROL — same parts on the CHAT plane (proves the fixture image is readable)")
st, body = req("POST", f"/api/sessions/{sid}/chat", {"input": parts}, timeout=180)
print("chat plane:", st, json.dumps(body)[:600])

print("\nDONE. Session used:", sid)
```

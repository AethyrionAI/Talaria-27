# OPUS T27-132 — the honesty floor: a caption-less image turn ships an explicit instruction, not a lone `image_url`

**Item:** OPEN_ITEMS **#132**. **Difficulty: OPUS** — a bounded request-body
change at known build sites. Ruled at the 2026-08-09 decision pass: *"ship the
floor now; `auxiliary.vision` is the keeper; #132 CLOSES when the floor
lands."* Written 2026-08-10.

## 1. Verified state

- **The defect (dossier, verified at HEAD 08-09):** a caption-less image turn
  ships a lone `image_url` part with **zero instruction**. That is why the
  host mints `[attachment]` / `[screenshot]` placeholder strings itself —
  closing this entry's own second finding. The model receives an image and no
  statement of what the user wants.
- **Build sites (grep `image_url`, 2026-08-10):**
  - `AttachmentInlining.swift:46` — maps attachments onto
    `{type:"text"}` / `{type:"image_url"}` parts (the shared support layer).
  - `SessionsHermesClient.swift:1917-2022` — `ChatTurnBody`'s part encoding
    (sessions plane).
  - `RunsTurnBody.make` — the runs plane builds its own parts (#290's lane
    touched its budgets). **The floor covers BOTH planes or it is half a
    floor.**
  - `LiveVoiceSessionService.swift:404` — the voice path also builds
    `image_url`; ⚠️ VERIFY AT LANE START whether a caption-less shape is
    reachable there (a spoken turn usually carries a transcript as text). If
    unreachable, record that and leave it alone.
- **The keeper context:** the Mac runs `auxiliary.vision` (device-proven,
  3-photo Z2 turn). The floor is independent of host config — it makes the
  REQUEST honest regardless of which model reads it. (OJAMD's vision config
  is a separate check, queued in the OJAMD handoff §10.)

## 2. Fix shape

When the user's text is EMPTY and image parts exist, the request includes an
explicit text part stating the fact: the user attached N image(s) with no
caption — examine and describe/act on them. Constraints that make it a floor
and not a fabrication:

- **Wire-only.** The local transcript renders exactly as today (the bubble
  already shows the image; `MessageBubble.swift:773`'s rendering is
  untouched). The instruction is transport framing, not user prose — the same
  category as the history scaffolding the request already carries.
- **Factual, fixed, minimal.** One neutral sentence template with the count.
  No guessed intent ("the user probably wants…"), no per-image invention —
  the real-data-only rule applies to wire text too.
- **Captioned turns are untouched.** Any non-empty user text suppresses the
  floor entirely.

## 3. Bars — copy into #132's entry before the run

- **132-A (RED→GREEN, unit, sessions plane):** a caption-less single-image
  turn's encoded `ChatTurnBody` contains a text part with the floor sentence
  + the image part. RED first (today: image part only).
- **132-B (unit, runs plane):** same assertion on `RunsTurnBody.make` — and
  the floor text COUNTS inside the existing attachment/body budget
  arithmetic, not on top of it (#290's uncounted-history lesson).
- **132-C (unit):** a captioned image turn's body is byte-identical to
  today's — the floor never fires when text exists.
- **132-D (unit):** multi-image count is right (N=3 → "3 images"), and a
  text-file-only attachment turn (no images) does NOT get the image floor.
- **132-E (render):** the local transcript for a caption-less image turn is
  unchanged — snapshot/assert the bubble does not display the floor text.
- **132-F:** `GATE: PASS`, counts MOVED. **Then #132 CLOSES** (the ruling
  says so) — close-out sweeps the entry's stale "host config question"
  framing, superseded by the keeper ruling.

## 4. Traps

- **Do not put the floor text into the stored `Message`.** It must be
  injected at ENCODE time only — if it lands in the model/store, it shows in
  the transcript, survives edits, and rides retries into doubled instructions.
- The host's own placeholder minting (`[attachment]`) will still exist
  server-side — the floor makes it moot for our turns, it does not remove it.
  Don't chase host behaviour from this lane.
- #173 (silent degradation on attachments the host cannot see) is adjacent
  and NOT this lane — the floor states what was sent; #173 is about what the
  host failed to read. Cross-reference, don't merge scopes.

## 5. Owen's to decide

The floor sentence's exact wording is the lane's to draft and the entry's to
record — flag it in the PR body for Owen's read, since it is text every
paired-host conversation will silently carry.

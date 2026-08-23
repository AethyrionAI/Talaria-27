# Voice subsystem — what is MEASURED, what is INFERRED, what is ASSUMED

**2026-08-22, at Owen's ask:** *"I think it would be wise to step back and
confirm everything, yeah?"*

**Why this shape rather than "re-check everything".** Six mechanisms on #138
were proposed and falsified in one day; #389 was nearly rebuilt because a
finished result sat under the wrong item; #348 was reframed the moment real
timestamps were matched; #383 shipped a defect that had been *written up as
fixed and never deployed*. The common thread is not carelessness — **every one
was a reasonable claim with no instrument that could have said no.** So the
audit that pays is not breadth. It is: *for each load-bearing claim, could it
have failed?*

Three grades:

- **MEASURED** — an instrument produced it, and that instrument could have
  returned the opposite.
- **INFERRED** — read from source or docs. Sound reasoning, no observation.
- **ASSUMED** — believed, never tested, and often not noticed as a claim.

---

## The table

| # | claim | grade | what it rests on | what would falsify it |
|---|---|---|---|---|
| 1 | Realtime voice works end to end on both hosts | **MEASURED** | Owen ran a full conversation on each | a failed session |
| 2 | Both hosts run plugin `fb2e364` | **MEASURED** | bogus-token dispatch probe + nonsense-verb control, both hosts | `unknown_event_type` on a real verb |
| 3 | `turnDetection` rides the readiness payload | **MEASURED** | `voice.readiness()` evaluated out-of-process on both hosts | field absent |
| 4 | #396-B moved no default | **MEASURED** | resolved dict byte-identical to #383's literal, asserted by test | any field differing |
| 5 | #138 is a feedback loop in ONE session | **MEASURED** | 7 cycles of `speech_started → response.created → audio.started`, one session, no fallback line | a fallback line, or a cycle without the ordering |
| 6 | The app can observe assistant playback | **MEASURED** | `#138 audio.started` arrives | its absence — which is what the fork test was built to detect |
| 7 | `server_vad @ 0.8` does not stop the loop | **MEASURED**, n=1 | one echo 0.52 s into playback | a longer clean session |
| 8 | AEC has a proper far-end reference | **INFERRED** | source: WebRTC renders the remote track; no `SpeechOutputService`/`AVAudioPlayer`/`AVAudioEngine` in the realtime path; empty `didAdd stream:` | never observed at runtime |
| 9 | Playback state is cleared early by `conversation.item.added` | **INFERRED** (strong) | source at `:825` + a log line at 19:56:33.285 reading "idle" 1.47 s into a playback | a direct trace of the reset firing |
| 10 | #397's fallback can leave a live realtime session | **INFERRED** | source: `start.cancel()` cancels a Task, not a peer connection | **never once observed in a log** |
| 11 | Local fault 1 has no knob (`SpeechDetector` gates on speech-presence) | **INFERRED** | Apple's own docs + the SDK enum | a device trial |
| 12 | Local `endpointSilence` 1.35 s is a *fallback*, not the primary endpointer | **INFERRED** | the code's own doc comment | **the discriminator line has never been read** — it ships, nobody has looked |
| 13 | **The echo is ACOUSTIC** | 🔴 **ASSUMED** | nothing | **138-L: one session with headphones** |
| 14 | **Battery rates describe the device** | 🔴 **ASSUMED** | nothing — and #398 shows it is false | the device is on `24A5418b`; every sim is beta5 or older |

---

## What the table says to do

**Row 13 is the one that matters.** Six mechanisms were proposed and every
single one assumed acoustic echo without testing it. It is the shared premise
underneath all six failures, it has never been interrogated, and **one session
with headphones settles it.** Nothing else on this list is worth more per
minute.

**Row 14 is the one nobody noticed was a claim.** Every battery number is
implicitly "…on the runtime we measured it on", and that runtime is no longer
the one Owen uses. Filed as #398. It cannot be fixed by a better instrument —
only by re-measuring on the device.

**Row 12 looked free. It is not, and the attempt is worth recording.**
`fallback endpointer fired (no final from transcriber)` already ships at
`.notice`, so I grepped all three archives for it: **zero hits in every one.**

That is *not* evidence the fallback never fires. **All three archives are
REALTIME sessions** — the local pipeline was never running, so the line could
not have appeared. A zero that was guaranteed by construction is exactly the
"green that proves nothing" shape, one layer down, and it would have been very
easy to write up as "the fallback endpointer never fires."

**What row 12 actually needs:** a session on the LOCAL engine — brain set to
on-device, or an unpaired profile — with a deliberate cut-off, then the grep.
The instrument is real and already shipping; it has simply never been pointed
at a session it can see.

**Row 10 deserves naming as a discipline point.** #397 was found from source,
fixed, and mutation-tested — and the condition it guards has never been
observed in a log. That is *not* a reason to doubt the fix (the code path is
unambiguous), but it is exactly the grade of claim that produced today's six
failures, and it should be labelled INFERRED rather than allowed to age into
"known".

---

## The rule this earns

**A mechanism claim on the voice path does not get made without a log line that
would have to change if it were false.** Row 13 is what it costs to skip that:
a day of reasonable, confident, wrong answers — each of which survived only
because the instrument that could have killed it did not exist yet.

Cross-references: **#138** (the six falsified mechanisms, and 138-L), **#396**
(local side, rows 11–12), **#397** (row 10), **#398** (row 14), **#343** (the
first contamination window), **#215** (a rate measured in a configuration the
system never enters).

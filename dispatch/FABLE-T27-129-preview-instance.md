# FABLE T27-129 — Voice preview must not touch the live session's audio

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-129-*`
**Dispatch date:** 2026-07-17 · **Tracks:** OPEN_ITEMS #129 · **Size:** micro-PR
**Baseline:** check `git log` for current (≥800/67) · **Toolchain:** Xcode-beta3.

## The bug (this was the #128 crash trigger)

`VoiceSettingsScreen:187` `speechOutput.previewVoice()` uses the CHAT
SpeechOutputService instance (`managesAudioSession = true`). During an active
voice session each preview flips the shared session `.playAndRecord →
.playback → back` under the running capture engine — the interruption burst
that lit #128's tap race, and even crash-free it degrades the live session.
The `isBlocked` gate protects `speak()` but not `previewVoice()`.

## The fix — option (a), Owen-approved direction

While a voice session is active, route previews through the pipeline's
`nativeSpeechOutput` instance (gate off, no session management) so the sample
plays OVER the live session without touching its configuration. Concretely:
the settings screen asks a small decision function which instance previews —
`TalkStore.isSessionActive ? nativeSpeechOutput : speechOutput` — injected,
not reached through globals; follow how AppContainer already wires both
instances. No session active → chat instance, unchanged (previews keep their
full `.playback` fidelity outside sessions, which is #130's whole point).

**Audio law (absolute, from #106):** do NOT alter `managesAudioSession` on
either instance, do not add session calls, do not touch the
`didActivateAudioSession` gate. Selection only.

## Tests

Pure selection function: session-active → native instance; inactive → chat
instance. Pin with the existing mock instances.

## Acceptance

- Suite green ≥ baseline; regen only if a test file adds (separate commit,
  aps-environment verified).
- Device check (Owen): mid-session, audition + apply voices — no crash
  (re-proves #128 under its original trigger), session keeps running, mic
  stays live afterward; outside a session, previews sound full-fidelity.

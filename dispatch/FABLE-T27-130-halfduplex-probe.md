# FABLE T27-130 — Fidelity probe: half-duplex + .default mode (A/B branch, NOT for merge)

**Repo:** `AethyrionAI/Talaria-27` · **Branch:** `probe/t27-130-halfduplex` (STAYS A PROBE —
Owen A/Bs it on device against main before any merge decision)
**Dispatch date:** 2026-07-17 · **Tracks:** OPEN_ITEMS #130 option (a) · **Size:** small probe
**Baseline:** ≥800/67 · **Toolchain:** Xcode-beta3.

## Purpose

In-session TTS is telephony-muddy because `.voiceChat` processes the downlink
(previews on `.playback` sound full-fidelity — the gap Owen hears). The
vpio-bypass probe already PROVED raw capture works on this seed with
`.default`. This probe trades hardware echo cancellation for crisp TTS and
software half-duplex, so Owen can hear both worlds and choose.

## The build (all inside NativeVoicePipelineService; nothing else)

1. Session config: `.playAndRecord` + mode `.default` (keep options); do NOT
   call `setVoiceProcessingEnabled` (see the dormant vpio-bypass shape in git
   history: `probe/t27-vpio-bypass` @ `9c5764a` — branch deleted, commit
   retrievable, or just re-derive: it was two edits).
2. Half-duplex gate: while `speechOutput.isSpeaking` (the native instance —
   find its actual speaking-state surface), DISCARD transcription results in
   the recognition callback (do not stop the tap or the engine — the mic
   stays hot, its text is just ignored; keeps restart machinery untouched).
   Add a short hangover (~300ms) after TTS ends before honoring text again,
   so the tail of the assistant's own audio can't self-transcribe.
3. Barge-in note: talk-over interruption will NOT work on this branch —
   that's the trade being evaluated, say so in the PR body, do not "fix" it.
4. All #105/#106/#128 machinery untouched: churn guards, ownership gate,
   adjacent remove/install.

## Tests

The half-duplex discard + hangover as a pure decision function
(speaking-state × timestamps → honor/discard), unit-tested. Session-mode
change itself is device-judged, not unit-tested.

## Acceptance

- Suite green ≥ baseline on the probe branch; PR opened but labeled
  DO-NOT-MERGE / probe.
- Device A/B (Owen): same conversation on main then on the probe —
  judge (1) TTS crispness, (2) whether `render err` flood is gone from logs,
  (3) how much losing talk-over barge-in hurts in real use, (4) mic
  sensitivity now that #106 is in (the old probe's 'very sensitive' note
  predates it). Owen's verdict decides: merge a productionized version,
  or close #130 as status-quo-accepted.

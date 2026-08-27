import Foundation
import Testing
@testable import Talaria

/// #56 sub-check (3) — **"Tailnet-unreachable: FAIL … unreachable is
/// indistinguishable from slow."**
///
/// The 2026-07-20 device sweep asked Siri a question with the phone off the
/// tailnet and off wifi. The intent answered *"Talaria is still working on it.
/// Open Talaria to watch it finish."* — the same words a genuinely slow but
/// alive run gets. Nothing was working; nothing ever would.
///
/// **Why the current code cannot do better, and why "classify the error
/// harder" is not the fix.** `AskHermesIntent.perform()` polls a 25 s budget
/// (`replyBudget`) and, on expiry, returns the hand-off. The send underneath it
/// is a `POST …/chat/stream`, and `SessionsHermesClient.makeRequest` stamps
/// that request with `requestTimeout(forAccept: "text/event-stream")` = **300 s**.
/// Against a black hole (packets dropped, no RST) URLSession produces no error
/// for five minutes, so `perform()`'s window closes with `.pending` every time
/// and the "still working" branch is the *only* branch a black hole can reach.
/// Bar 56-U-A pins that arithmetic — and pins it in both directions, because
/// the tempting shortcut (shrink `streamingRequestTimeout` to fit the budget)
/// is the trap `SessionsHermesClient`'s own #145 comment names: it would kill
/// live SSE turns and present as a network bug.
///
/// **The second collapse is the words.** When a transport error *does* land in
/// time, `SessionsHermesClient.failureMessage(for:)` hands the user
/// `error.localizedDescription` verbatim and `AskHermesIntentError.hermesFailed`
/// speaks it. Measured on the 27A5228h toolchain, 2026-08-06:
///
/// | how the error was made | `.timedOut` | `.cannotConnectToHost` |
/// |---|---|---|
/// | live `URLSession` (real socket) | `"The request timed out."` | `"Could not connect to the server."` |
/// | synthesized `URLError(code)` (what a `URLProtocol` stub emits) | `"The operation couldn’t be completed. (NSURLErrorDomain error -1001.)"` | `"…error -1004.)"` |
///
/// None of the four names a cause the owner can act on. Bar 56-U-B pins that.
///
/// **What this file is.** RED tests, written before the fix. 56-U-A and 56-U-B
/// characterize the shipping behaviour and are expected to pass today — they
/// are the premise, and they stay in the suite after GREEN as the guard against
/// the shortcut. 56-U-C/D/E/F/G name API that does not exist yet
/// (`HostReachability`, `HostReachabilityFailure`,
/// `AskHermesIntent.unreachableDialog(for:)`, `.stillWorkingDialog`,
/// `.keyRestoreBudget`, `.needsReachabilityPreflight(hermesAPIKey:)`) and so
/// fail at COMPILE — the whole honest-error surface is new, which is the one
/// case where a compile-RED is the honest witness. Every new static must be
/// `nonisolated` to be reachable from these non-`@MainActor` tests, the same
/// way `resolveOutcome`/`spokenSummary` already are.
///
/// **Found while scoping, and it bounds what this lane should claim.**
/// `ChatBackendRouter.resolveBrainForNextTurn` (ChatBackendRouter.swift:223)
/// ALREADY routes new turns to the on-device brain when Hermes is
/// known-unreachable, announcing it (#192). It just never fires for the Siri
/// turn that matters, because `connectionStatus` only flips to `.error` in
/// `streamTurn`'s catch — i.e. 300 s in, long after Siri gave up. So a bounded
/// preflight is the prerequisite for BOTH answers: the honest error this lane
/// builds, and the better one it deliberately does not (route the ask to the
/// local brain and say so). Nothing pinned below forecloses that follow-on;
/// see the report's Tier 2 note.
///
/// **Fixture note (#166b).** Every unreachable shape here is a `URLProtocol`
/// stub, never a socket. A real black-hole probe wants an unroutable address
/// (TEST-NET-1 `192.0.2.1` behaves correctly outside the harness — verified),
/// but inside the app test host ATS is scoped to `100.64.0.0/10`, so any such
/// address is refused with `-1022` *before* the timeout and the fixture would
/// silently measure the wrong failure. No service is stopped for these tests.
@Suite(.serialized)
struct AskHermesUnreachableHonestyTests {

    // MARK: - Fixtures

    /// Fails or answers on command. `delay` exists so the "fast-fail" bar
    /// measures something: a stub that fails on the same tick cannot tell a
    /// bounded preflight from an unbounded one.
    private final class ReachabilityStubURLProtocol: URLProtocol, @unchecked Sendable {
        struct Script: Sendable {
            var statusCode: Int?
            var error: URLError?
            var delay: Duration = .milliseconds(120)
        }

        nonisolated(unsafe) static var script = Script(statusCode: 200, error: nil)
        nonisolated(unsafe) static var requestCount = 0

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.requestCount += 1
            let script = Self.script
            let seconds = Double(script.delay.components.seconds)
                + Double(script.delay.components.attoseconds) / 1e18
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self, let client = self.client else { return }
                if let error = script.error {
                    client.urlProtocol(self, didFailWithError: error)
                    return
                }
                let response = HTTPURLResponse(
                    url: self.request.url!,
                    statusCode: script.statusCode ?? 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                // Padded past the transport flush threshold — a sub-512B stub
                // body can sit unflushed and the response never lands.
                let body = #"{"data":[],"_pad":""# + String(repeating: "-", count: 700) + #""}"#
                client.urlProtocol(self, didLoad: Data(body.utf8))
                client.urlProtocolDidFinishLoading(self)
            }
        }

        override func stopLoading() {}

        static func reset() {
            script = Script(statusCode: 200, error: nil)
            requestCount = 0
        }
    }

    private static func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReachabilityStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// The vocabulary an honest message has to reach for. Deliberately the
    /// owner's own words for the three real causes (`OPEN_ITEMS.md` #56):
    /// tailnet down / host asleep / not on the VPN — plus "not running" for
    /// the refused shape, which is the fourth thing that actually happens.
    private static let actionableTokens = [
        "tailnet", "tailscale", "vpn", "asleep", "sleep",
        "running", "network connection", "offline", "listening",
    ]

    private static func namesACause(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return actionableTokens.contains { lowered.contains($0) }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    // MARK: - 56-U-A — the arithmetic that makes "classify harder" insufficient

    /// **Bar 56-U-A.** The streaming turn's transport budget exceeds the
    /// intent's reply budget by more than 10×, so a black-holed host cannot
    /// surface *any* transport error inside `perform()`'s window — the
    /// "still working" hand-off is the only branch it can reach. Expected
    /// GREEN today: this characterizes the bug rather than the fix.
    ///
    /// It stays in the suite after the fix as a **guard on the rejected
    /// option**: if a later lane closes #56 by shrinking
    /// `streamingRequestTimeout` into the intent's budget, this fails and
    /// forces the #145 trade back into the open (short SSE budgets kill live
    /// turns and present as a network bug).
    @Test func streamingTransportBudgetDwarfsTheIntentReplyBudget() {
        let streaming = SessionsHermesClient.requestTimeout(forAccept: "text/event-stream")
        let interactive = SessionsHermesClient.requestTimeout(forAccept: "application/json")
        let budget = Self.seconds(AskHermesIntent.replyBudget)

        #expect(budget == 25)
        #expect(streaming == 300)
        #expect(interactive == 20)

        // The mechanism, stated as an inequality: a stream POST cannot report
        // a dead host before the intent has already answered Siri.
        #expect(streaming > budget * 10)

        // And the reused-hop case is the common one: with a live journal hop
        // there is no session-create call, so the 20s interactive budget —
        // the only one that would fit — is never on the path at all.
        #expect(interactive < budget)
    }

    // MARK: - 56-U-B — what the user is told today

    /// **Bar 56-U-B.** The text `AskHermesIntentError.hermesFailed` speaks is
    /// `URLError.localizedDescription`, unmodified. Neither the live strings
    /// nor the synthesized ones name a cause the owner can act on. Expected
    /// GREEN today; after the fix it still holds, because the fix does not
    /// change Foundation — it stops *routing the user through* these strings.
    @Test func todaysTransportTextNamesNoActionableCause() {
        // Measured on 27A5228h, 2026-08-06, against a real socket: a dead
        // loopback port (refused) and TEST-NET-1 192.0.2.1:8642 (black hole).
        let liveStrings = [
            "The request timed out.",
            "Could not connect to the server.",
        ]
        for text in liveStrings {
            #expect(Self.namesACause(text) == false, "live text unexpectedly actionable: \(text)")
        }

        // What a URLProtocol stub — and therefore every test in this repo that
        // synthesizes a transport failure — actually puts in front of the user.
        for code in [URLError.Code.timedOut, .cannotConnectToHost, .notConnectedToInternet] {
            let described = URLError(code).localizedDescription
            #expect(Self.namesACause(described) == false)
            #expect(described.contains("NSURLErrorDomain"))
        }
    }

    // MARK: - 56-U-C — the classifier (RED: HostReachability does not exist)

    /// **Bar 56-U-C.** Each `URLError` variant the tailnet actually produces
    /// maps to its own honest shape, and each shape speaks a distinct sentence
    /// that names a cause. MET only when every mapping asserts AND every
    /// `spokenDetail` is non-empty, mutually distinct, and hits the actionable
    /// vocabulary. A shape whose sentence could be swapped for another's is a
    /// miss — that is the same collapse in new clothes.
    @Test func eachTransportShapeGetsItsOwnHonestSentence() {
        let expected: [(URLError.Code, HostReachabilityFailure)] = [
            (.timedOut, .noAnswer),
            (.cannotConnectToHost, .refused),
            (.cannotFindHost, .hostNotFound),
            (.dnsLookupFailed, .hostNotFound),
            (.notConnectedToInternet, .deviceOffline),
            (.networkConnectionLost, .connectionLost),
        ]
        for (code, shape) in expected {
            #expect(HostReachability.classify(code) == shape, "\(code.rawValue) misclassified")
        }

        let shapes: [HostReachabilityFailure] = [
            .noAnswer, .refused, .hostNotFound, .deviceOffline, .connectionLost,
        ]
        var seen = Set<String>()
        for shape in shapes {
            let spoken = shape.spokenDetail
            #expect(spoken.isEmpty == false)
            #expect(Self.namesACause(spoken), "not actionable: \(spoken)")
            #expect(seen.insert(spoken).inserted, "two shapes speak the same sentence: \(spoken)")
        }

        // The black-hole shape is the one the device sweep hit. It has to name
        // the tailnet or the sleeping host — that is the whole item.
        let noAnswer = HostReachabilityFailure.noAnswer.spokenDetail.lowercased()
        #expect(noAnswer.contains("tailnet") || noAnswer.contains("tailscale") || noAnswer.contains("asleep"))
    }

    // MARK: - 56-U-D — fast-fail inside the intent's budget (RED)

    /// **Bar 56-U-D.** A black-holed host is called unreachable in a bounded
    /// time strictly inside `AskHermesIntent.replyBudget`, with real headroom.
    /// Two halves: the declared budget must fit, and a live probe against a
    /// stub that times out must actually return inside it. Measured with a
    /// clock, not asserted by construction.
    @Test func blackHoledHostFailsFastAndIsNamedUnreachable() async {
        #expect(HostReachability.preflightBudget < AskHermesIntent.replyBudget)
        // Headroom, not just ordering: the preflight is one of several things
        // perform() does before the send, so it may not eat the budget.
        #expect(Self.seconds(HostReachability.preflightBudget) <= Self.seconds(AskHermesIntent.replyBudget) / 5)

        ReachabilityStubURLProtocol.reset()
        ReachabilityStubURLProtocol.script = .init(
            statusCode: nil,
            error: URLError(.timedOut),
            delay: .milliseconds(150)
        )
        defer { ReachabilityStubURLProtocol.reset() }

        let clock = ContinuousClock()
        let started = clock.now
        let verdict = await HostReachability.probe(
            baseURL: "http://100.110.102.59:8642",
            apiKey: "key-test",
            session: Self.stubbedSession(),
            timeout: HostReachability.preflightBudget
        )
        let elapsed = clock.now - started

        #expect(verdict == .unreachable(.noAnswer))
        #expect(elapsed < AskHermesIntent.replyBudget)
        #expect(ReachabilityStubURLProtocol.requestCount == 1, "the preflight must be ONE round trip")
    }

    // MARK: - 56-U-F — the preflight is paid for OUT of the budget (RED)

    /// **Bar 56-U-F.** iOS reaps a background intent `perform()` at roughly
    /// 30 s, and `replyBudget` is 25 s specifically to leave headroom for
    /// result delivery. Today the budget poll starts only AFTER
    /// `waitForAPIKeyRestore`'s 2 s window, so the worst case is already ~27 s.
    /// Adding a preflight on top would push it past the cap and turn an
    /// honesty fix into a reaped intent — a strictly worse bug.
    ///
    /// So the pre-send waits must fit INSIDE `replyBudget`, not extend it:
    /// every bounded wait in `perform()` shares one deadline taken at entry.
    /// This bar is the arithmetic that forces that structure, and it needs the
    /// 2 s key-restore literal promoted to a named constant to be checkable at
    /// all — which is the point.
    @Test func preflightAndKeyRestoreFitInsideTheReplyBudget() {
        let preSend = AskHermesIntent.keyRestoreBudget + HostReachability.preflightBudget
        #expect(preSend < AskHermesIntent.replyBudget)
        // And the whole perform() stays clear of the ~30s system cap.
        #expect(Self.seconds(AskHermesIntent.replyBudget) <= 25)
    }

    // MARK: - 56-U-G — the hostless user must never be preflighted (RED)

    /// **Bar 56-U-G, and the one that matters most for the launch default.**
    /// `ChatBackendRouter` (wired at AppContainer.swift:607, enforced at
    /// ChatBackendRouter.swift:213 `guard isHermesConfigured()` in
    /// `resolveBrainForNextTurn`) routes a turn to
    /// `LocalChatBackend` whenever the Sessions-API key is empty — the
    /// self-contained-brain-first posture. A reachability preflight that ran
    /// unconditionally would probe an unset base URL, call it unreachable, and
    /// tell a hostless user their on-device brain is down. That is a WORSE
    /// dishonesty than the one this lane is fixing, and it would land on the
    /// default user rather than the tailnet edge case.
    ///
    /// So the preflight is gated on the same signal the router uses. Pure
    /// predicate, so the gate is checkable without an `AppContainer`.
    @Test func preflightIsSkippedWhenTheTurnWillRouteToTheLocalBrain() {
        #expect(AskHermesIntent.needsReachabilityPreflight(hermesAPIKey: "") == false)
        #expect(AskHermesIntent.needsReachabilityPreflight(hermesAPIKey: "   \n ") == false)
        #expect(AskHermesIntent.needsReachabilityPreflight(hermesAPIKey: "sk-live-key") == true)
    }

    // MARK: - 56-U-E — no false positives (RED)

    /// **Bar 56-U-E, half one.** A host that ANSWERS is reachable, whatever it
    /// answers. 401, 404, 500, 503 are all evidence the socket, the tailnet and
    /// the listener are alive; treating any of them as "unreachable" would
    /// re-break the thing this lane is fixing, in the other direction.
    @Test func anyHTTPAnswerCountsAsReachable() async {
        ReachabilityStubURLProtocol.reset()
        defer { ReachabilityStubURLProtocol.reset() }

        for status in [200, 204, 401, 403, 404, 500, 502, 503] {
            ReachabilityStubURLProtocol.script = .init(
                statusCode: status,
                error: nil,
                delay: .milliseconds(20)
            )
            let verdict = await HostReachability.probe(
                baseURL: "http://100.110.102.59:8642",
                apiKey: "key-test",
                session: Self.stubbedSession(),
                timeout: HostReachability.preflightBudget
            )
            #expect(verdict == .reachable(statusCode: status), "status \(status) must be reachable")
        }
    }

    /// **Bar 56-U-E, half two.** A reachable verdict produces NO unreachable
    /// dialog, so a slow-but-alive turn keeps the existing hand-off wording
    /// byte for byte. This is the bar that stops the fix from becoming a new
    /// dishonesty: the long-run hand-off is CORRECT behaviour (#56 sub-check
    /// (1) passed) and must survive untouched.
    @Test func aReachableHostNeverProducesAnUnreachableDialog() {
        #expect(AskHermesIntent.unreachableDialog(for: .reachable(statusCode: 200)) == nil)
        #expect(AskHermesIntent.unreachableDialog(for: .reachable(statusCode: 503)) == nil)

        // The hand-off string the device sweep photographed, promoted to a
        // named constant so a future edit to it fails a test instead of
        // silently re-colliding with the unreachable path.
        #expect(
            AskHermesIntent.stillWorkingDialog
                == "Talaria is still working on it. Open the app to watch it finish."
        )

        // And every unreachable shape says something ELSE — the collapse the
        // device sweep recorded, pinned shut.
        for shape in [HostReachabilityFailure.noAnswer, .refused, .hostNotFound, .deviceOffline, .connectionLost] {
            guard let spoken = AskHermesIntent.unreachableDialog(for: .unreachable(shape)) else {
                Issue.record("no dialog for \(shape)")
                continue
            }
            #expect(spoken != AskHermesIntent.stillWorkingDialog)
            #expect(Self.namesACause(spoken), "unreachable dialog not actionable: \(spoken)")
        }
    }
}

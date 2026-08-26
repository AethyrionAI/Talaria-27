import Foundation
import Testing
@testable import Talaria

/// **Bar 309-B3 — the probe ladder makes REAL discriminations.**
///
/// The design shows three named checks so that a failure can point at the one
/// that broke. This suite is what makes that promise true rather than
/// decorative: four arms, each a different wire outcome, each producing a
/// DIFFERENT ladder — and two of them leaving a rung explicitly NOT CONCLUDED
/// rather than ticking it.
///
/// RED against `main`: `probeCandidateHost` does not exist there.
@MainActor
struct ConnectHostProbeTests {

    /// File-local by house convention — `AppStoresTests` and
    /// `TalariaPlatformLinkTests` each keep their own, so a change to one
    /// suite's wire fixture cannot silently move another's.
    final class StubURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requestHandler:
            (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    final class MutableBox<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    nonisolated static let catalog = """
    {"provider":"kimi-coding","model":"k2",
     "providers":[
       {"slug":"kimi","name":"Kimi","authenticated":true,"models":["k2","k2-turbo"]},
       {"slug":"deepseek","name":"DeepSeek","authenticated":true,"models":["v4","v4-flash","v4-lite"]}
     ]}
    """

    // MARK: Arm 1 — nothing answered

    @Test func aTransportFailureFailsOnlyTheFirstRungAndReachesNoOther() async throws {
        StubURLProtocol.requestHandler = { _ in throw URLError(.timedOut) }
        defer { StubURLProtocol.requestHandler = nil }

        let outcome = await GatewayHermesHostService.probeCandidateHost(
            gatewayBaseURL: "http://sleeping.tailnet.test:8642",
            apiKey: "any-key",
            session: session()
        )

        #expect(outcome == .noAnswer(detail: "TIMED OUT"))
        let ladder = outcome.ladder
        #expect(ladder.reachable == .failed("TIMED OUT"))
        // NOT `failed` — the other two rungs never ran, and saying they failed
        // would point the user at a key that was never offered to anyone.
        #expect(ladder.keyAccepted == .notReached)
        #expect(ladder.hermesGateway == .notReached)
        #expect(outcome.guiltyField == .gatewayURL)
        #expect(outcome.latencyMilliseconds == nil, "nothing came back — there is no latency to report")
    }

    /// A refused connection is not a timeout, and the ladder says which.
    @Test func aRefusedConnectionReadsAsNoAnswerRatherThanATimeout() async throws {
        StubURLProtocol.requestHandler = { _ in throw URLError(.cannotConnectToHost) }
        defer { StubURLProtocol.requestHandler = nil }

        let outcome = await GatewayHermesHostService.probeCandidateHost(
            gatewayBaseURL: "http://nothing.tailnet.test:8642",
            apiKey: "any-key",
            session: session()
        )
        #expect(outcome == .noAnswer(detail: "NO ANSWER"))
    }

    // MARK: Arm 2 — the key is refused

    @Test func a401PassesReachabilityFailsTheKeyAndConcludesNothingAboutHermes() async throws {
        StubURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            #expect(url.absoluteString == "http://ojamd.tailnet.test:8642/api/model/options")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer wrong-key")
            return (HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { StubURLProtocol.requestHandler = nil }

        let outcome = await GatewayHermesHostService.probeCandidateHost(
            gatewayBaseURL: "http://ojamd.tailnet.test:8642",
            apiKey: "wrong-key",
            session: session()
        )

        guard case .keyRefused(let ms) = outcome else {
            Issue.record("expected keyRefused, got \(outcome)")
            return
        }
        #expect(ms >= 0)
        let ladder = outcome.ladder
        #expect(ladder.reachable.isPassed, "something answered — that IS reachability")
        #expect(ladder.keyAccepted == .failed("REFUSED"))
        // **The load-bearing line of this suite.** A 401 from an unknown
        // listener says something is guarding that port; it does NOT say the
        // port is Hermes. Ticking the third rung here would be the theater the
        // bar forbids.
        #expect(ladder.hermesGateway == .notConcluded)
        #expect(outcome.guiltyField == .apiKey)
    }

    @Test func a403IsTheSameVerdictAsA401() async throws {
        StubURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            return (HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { StubURLProtocol.requestHandler = nil }

        let outcome = await GatewayHermesHostService.probeCandidateHost(
            gatewayBaseURL: "http://ojamd.tailnet.test:8642", apiKey: "k", session: session())
        if case .keyRefused = outcome {} else { Issue.record("expected keyRefused, got \(outcome)") }
    }

    // MARK: Arm 3 — something is there, but it is not Hermes

    /// The 200-with-the-wrong-body case, and the reason the KEY rung reports
    /// `notConcluded` rather than a tick: a server that answers 200 without
    /// reading the `Authorization` header has not accepted the key — it has
    /// ignored it.
    @Test func a200ThatIsNotAModelCatalogFailsTheShapeAndConcludesNothingAboutTheKey() async throws {
        StubURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("<html><body>It works!</body></html>".utf8))
        }
        defer { StubURLProtocol.requestHandler = nil }

        let outcome = await GatewayHermesHostService.probeCandidateHost(
            gatewayBaseURL: "http://ojamd.tailnet.test:8000", apiKey: "k", session: session())

        guard case .notHermes = outcome else {
            Issue.record("expected notHermes, got \(outcome)")
            return
        }
        let ladder = outcome.ladder
        #expect(ladder.reachable.isPassed)
        #expect(ladder.keyAccepted == .notConcluded,
                "a server that ignored the bearer never tested it")
        #expect(ladder.hermesGateway == .failed("WRONG SHAPE"))
        // The design's note on B6: name the suspect character — the PORT — not
        // an HTTP code. Nothing in the ladder quotes a status.
        #expect(!ladder.hermesGateway.detailLabel.contains("200"))
        #expect(outcome.guiltyField == .gatewayURL)
    }

    @Test func a404IsNotHermesRatherThanUnreachable() async throws {
        StubURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { StubURLProtocol.requestHandler = nil }

        let outcome = await GatewayHermesHostService.probeCandidateHost(
            gatewayBaseURL: "http://ojamd.tailnet.test:8642", apiKey: "k", session: session())
        if case .notHermes = outcome {} else { Issue.record("expected notHermes, got \(outcome)") }
        #expect(outcome.ladder.reachable.isPassed, "a 404 still means something answered")
    }

    // MARK: Arm 4 — green

    @Test func aHermesCatalogPassesAllThreeRungsAndCountsTheModels() async throws {
        let requests = MutableBox(0)
        StubURLProtocol.requestHandler = { request in
            requests.value += 1
            let url = try #require(request.url)
            // The trailing slash on the typed address must not produce
            // `//api/model/options`, which 404s and would read as "not Hermes".
            #expect(url.absoluteString == "http://ojamd.tailnet.test:8642/api/model/options")
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(Self.catalog.utf8))
        }
        defer { StubURLProtocol.requestHandler = nil }

        let outcome = await GatewayHermesHostService.probeCandidateHost(
            gatewayBaseURL: "http://ojamd.tailnet.test:8642/",
            apiKey: "real-key",
            session: session()
        )

        guard case .connected(let ms, let models) = outcome else {
            Issue.record("expected connected, got \(outcome)")
            return
        }
        // ONE request answers all three questions — bar 309-B3's shape.
        #expect(requests.value == 1)
        #expect(ms >= 0)
        #expect(models == 5, "2 kimi + 3 deepseek — the card's MODELS SEEN")
        let ladder = outcome.ladder
        #expect(ladder.reachable.isPassed)
        #expect(ladder.keyAccepted == .passed("ACCEPTED"))
        #expect(ladder.hermesGateway == .passed("5 SEEN"))
        #expect(outcome.guiltyField == nil)
    }

    // MARK: The budget, and the URL

    /// The copy says "the phone waited five seconds". That number and the
    /// probe's budget are ONE fact; this is what stops them drifting apart.
    @Test func theProbeBudgetIsTheNumberTheCopyPrints() {
        #expect(BootstrapProbeSession.requestTimeout == 5)
        #expect(ConnectHostCopy.fiveSecondsAtMost.contains("Five seconds"))
        #expect(ConnectHostCopy.noAnswerBlurb.contains("five seconds"))
    }

    @Test func theProbeURLRefusesAddressesItCannotForm() {
        #expect(GatewayHermesHostService.probeURL(gatewayBaseURL: "") == nil)
        #expect(GatewayHermesHostService.probeURL(gatewayBaseURL: "   ") == nil)
        #expect(GatewayHermesHostService.probeURL(gatewayBaseURL: "ojamd:8642") == nil)
        #expect(GatewayHermesHostService.probeURL(gatewayBaseURL: "ftp://ojamd:8642") == nil)
        #expect(
            GatewayHermesHostService.probeURL(gatewayBaseURL: "http://ojamd:8642//")?.absoluteString
                == "http://ojamd:8642/api/model/options"
        )
    }

    /// An unformable address never touches the network — and reports the one
    /// verdict that is true of it.
    @Test func anUnformableAddressAsksNothing() async {
        let requests = MutableBox(0)
        StubURLProtocol.requestHandler = { request in
            requests.value += 1
            let url = try #require(request.url)
            return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { StubURLProtocol.requestHandler = nil }

        let outcome = await GatewayHermesHostService.probeCandidateHost(
            gatewayBaseURL: "not-a-url", apiKey: "k", session: session())

        #expect(requests.value == 0)
        #expect(outcome.isNoAnswer)
    }
}

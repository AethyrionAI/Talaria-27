import Foundation
import os

/// **#309 Lane B, bar 309-B3 — the Connect Host probe ladder.**
///
/// Lane C's `fetchCurrentHost()` answers ONE question honestly ("does `:8642`
/// answer?") and says so in its own header: `/health` is unauthenticated, so a
/// 2xx there proves reachability and nothing about the key. This extension is
/// the ladder that header promised — three verdicts from ONE request, which is
/// possible because `GET /api/model/options` is authenticated AND Hermes-shaped:
///
/// | what happened                              | reachable | key           | Hermes  |
/// |--------------------------------------------|-----------|---------------|---------|
/// | transport error / 5 s timeout              | FAILED    | not reached   | not reached |
/// | 401 / 403                                  | passed    | REFUSED       | not concluded |
/// | 2xx that will not decode / any other status| passed    | not concluded | WRONG SHAPE |
/// | 2xx that decodes as a model catalog        | passed    | ACCEPTED      | n SEEN  |
///
/// **Two rungs deliberately report `notConcluded` rather than a tick.** A
/// server that returns 200 without reading the `Authorization` header has not
/// accepted the key, and a 401 from an unknown listener does not make it
/// Hermes. Ticking those would make the ladder decoration — the failure mode
/// the bar was written against.
///
/// **The timeout is `BootstrapProbeSession.requestTimeout` (5 s) and the copy
/// says "five seconds".** Those two numbers are one fact; if the budget ever
/// moves, the strings in `ConnectHostCopy` move with it.
extension GatewayHermesHostService {

    private static let probeLogger = Logger(
        subsystem: TalariaLog.subsystem, category: "ConnectHostProbe")

    /// The one authenticated round trip behind every Connect Host verdict.
    ///
    /// Never throws: each failure shape is a VERDICT the screen renders
    /// differently, and an error would collapse three answers into one.
    static func probeCandidateHost(
        gatewayBaseURL: String,
        apiKey: String,
        session: URLSession = BootstrapProbeSession.make(),
        now: @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) async -> HostProbeOutcome {
        guard let url = probeURL(gatewayBaseURL: gatewayBaseURL) else {
            // A URL this build cannot form was never sent, so there is no
            // latency to report and nothing answered — which is exactly
            // `noAnswer`. The screen's own validation stops this from being
            // reachable in practice; it is here so the function is total.
            return .noAnswer(detail: "BAD ADDRESS")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = BootstrapProbeSession.requestTimeout

        let started = now()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let detail = (error as? URLError)?.code == .timedOut ? "TIMED OUT" : "NO ANSWER"
            probeLogger.notice("probe: nothing answered (\(detail, privacy: .public))")
            return .noAnswer(detail: detail)
        }
        let elapsed = milliseconds(from: started, to: now())

        guard let http = response as? HTTPURLResponse else {
            return .notHermes(latencyMilliseconds: elapsed)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            return .keyRefused(latencyMilliseconds: elapsed)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            probeLogger.notice("probe: answered \(http.statusCode, privacy: .public) — not a Hermes catalog")
            return .notHermes(latencyMilliseconds: elapsed)
        }
        guard let catalog = try? JSONDecoder().decode(GatewayModelCatalog.self, from: data) else {
            return .notHermes(latencyMilliseconds: elapsed)
        }

        return .connected(
            latencyMilliseconds: elapsed,
            modelsSeen: catalog.providers.reduce(0) { $0 + $1.models.count }
        )
    }

    /// `{base}/api/model/options`, tolerating a trailing slash on the base —
    /// `//api/...` 404s on the api_server, which would read as "not Hermes"
    /// for a host that is perfectly fine.
    // harness-visible
    static func probeURL(gatewayBaseURL: String) -> URL? {
        var base = gatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty,
              let url = URL(string: base + "/api/model/options"),
              url.scheme?.hasPrefix("http") == true,
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    private static func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Int {
        let components = start.duration(to: end).components
        let millis = components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
        return max(0, Int(millis))
    }
}

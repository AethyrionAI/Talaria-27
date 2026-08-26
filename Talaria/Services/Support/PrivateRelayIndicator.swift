import Foundation

/// **#377 — naming iCloud Private Relay instead of presenting a generic
/// failure.** Private Relay proxies unencrypted app HTTP through
/// `mask.icloud.com`, which has no route into a tailnet, so cleartext HTTP to a
/// Tailscale address fails in a way that looks like an ordinary outage. The row
/// this type feeds exists to stop the user debugging the wrong thing.
///
/// **Scope, re-derived at HEAD (2026-08-26) rather than inherited from #24e.**
/// #24e's two measured victims — 502s from the relay `:8000` and 30-second
/// timeouts from the shim `:8765` — are both RETIRED components (#375), and the
/// sensor upload path is deleted (#352). Exactly one interceptable path
/// survives: **cleartext HTTP to a `100.64.0.0/10` literal on `:8642`**, which
/// carries chat, the runs plane, the Test Connection probe and the plugin
/// webhook. The narrowing makes this row matter more, not less.
///
/// **The honesty rule this type exists to enforce: a generic timeout is NOT
/// Private Relay.** iOS ships no public API for "is Private Relay on", so any
/// claim here has to come from evidence. Nothing else in the app may name the
/// condition; it names it only where the evidence discriminates, and says the
/// weaker thing everywhere else.
enum PrivateRelayIndicator {

    // MARK: - Verdict

    enum Verdict: Equatable, Sendable {
        /// The evidence discriminates: a proxy-shaped gateway status came back
        /// from a request Hermes would never answer that way.
        case indicated
        /// The PATH is interceptable and the failure is consistent with
        /// interception — but equally consistent with a dead host. States the
        /// configuration fact; claims nothing.
        case pathExposed

        var label: String {
            switch self {
            case .indicated: "PRIVATE RELAY"
            case .pathExposed: "PATH EXPOSED"
            }
        }

        var detail: String {
            switch self {
            case .indicated:
                """
                That status came from a proxy, not from Hermes. iCloud Private \
                Relay intercepts cleartext HTTP to Tailscale addresses and has \
                no route into your tailnet. Turn it off for this network under \
                Settings › Apple Account › iCloud › Private Relay.
                """
            case .pathExposed:
                """
                This is cleartext HTTP to a Tailscale address, which iCloud \
                Private Relay intercepts. That is one possible cause of the \
                failure above — a sleeping host or a firewall are others.
                """
            }
        }
    }

    // MARK: - The three legs

    /// Tailscale's CGNAT range, `100.64.0.0/10` — the same range `project.yml`
    /// scopes the ATS exception to (#166b). A literal only: a MagicDNS name has
    /// no exception and is ATS-blocked app-wide, so it fails before Private
    /// Relay is ever reached.
    static func isTailnetCGNAT(host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 100 && (64...127).contains(octets[1])
    }

    /// True when this request is one Private Relay can intercept at all:
    /// **cleartext `http`** to a **CGNAT literal**.
    ///
    /// The `https` leg is the strongest discriminator we have. Private Relay
    /// proxies unencrypted app traffic; TLS traffic goes direct, which is why
    /// the OTA install over `tailscale serve` has never been affected. A
    /// failure over `https` is therefore not this condition, whatever else it
    /// might be.
    static func pathIsInterceptable(baseURL: String) -> Bool {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "http",
              let host = url.host
        else { return false }
        return isTailnetCGNAT(host: host)
    }

    /// A status only an intermediary produces for this request. Hermes'
    /// aiohttp api_server answers `/v1/models` with 200 or 401 — a 502 there is
    /// something else talking, which is exactly what #24e measured.
    ///
    /// **503 is deliberately excluded.** A real server says 503 all the time
    /// (starting up, overloaded), so it does not discriminate; 502 and 504 are
    /// the statuses whose whole meaning is "I am a middle box and the thing
    /// behind me did not answer."
    static func isProxyShaped(status: Int) -> Bool {
        status == 502 || status == 504
    }

    // MARK: - The verdict

    /// `nil` means say nothing — which is most of the time, and is the point.
    ///
    /// **Why the silent cases are silent:**
    /// - `refused` and `authRejected` are *answers*. Something on the path
    ///   replied immediately, which is not the proxy's black-hole shape.
    /// - `hostNotFound` is DNS, and a CGNAT literal never resolves anything.
    /// - `notConfigured` has no request to reason about.
    /// - a PASSED test proves the path works, so there is nothing to explain.
    static func verdict(baseURL: String, failure: ConnectionTestFailure) -> Verdict? {
        guard pathIsInterceptable(baseURL: baseURL) else { return nil }
        switch failure {
        case .unexpectedStatus(let code):
            return isProxyShaped(status: code) ? .indicated : nil
        case .timedOut, .other:
            // No answer inside the budget is what a route-less proxy looks
            // like — and equally what a powered-down host looks like. Name the
            // exposure, never the cause.
            return .pathExposed
        case .refused, .hostNotFound, .authRejected, .notConfigured:
            return nil
        }
    }
}

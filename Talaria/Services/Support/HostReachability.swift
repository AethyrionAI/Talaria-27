import Foundation

// MARK: - Host reachability (#56)

/// Why a host could not be reached, in the shapes that have DIFFERENT fixes.
///
/// #145/#136 established the principle for Test Connection: a refused
/// connection, a black hole and a name that never resolved are three problems
/// with three remedies, and collapsing them into one "failed" is what made the
/// old silent button useless. #56 found the same collapse one plane over — the
/// Ask-Hermes intent handed the user `URLError.localizedDescription` verbatim
/// ("The request timed out.") which names no cause at all — so the vocabulary
/// lives here now, shared by both surfaces, and `UplinkSettingsScreen` maps
/// onto it rather than keeping a second classifier that could drift.
enum HostReachabilityFailure: Equatable, Sendable {
    /// Nothing came back inside the budget. THE tailnet-down signature: with
    /// Tailscale off, packets to a `100.64.0.0/10` address are dropped rather
    /// than refused, so the connect hangs instead of failing.
    case noAnswer
    /// The address answered at the network layer and refused the port — the
    /// host is up, the listener is not.
    case refused
    /// The name never resolved.
    case hostNotFound
    /// The device itself has no usable network.
    case deviceOffline
    /// The connection was established and then dropped mid-request.
    case connectionLost
    /// ATS refused before a packet left the device. Reachable only for hosts
    /// outside the `100.64.0.0/10` exception (#166b) — a LAN IP or a MagicDNS
    /// name typed into the gateway field will land here.
    case blockedByATS
    /// Nothing to probe: no base URL, or one that isn't a valid address.
    case notConfigured(String)
    /// Anything else, carrying the raw `URLError` code so the report is still
    /// specific enough to act on.
    case other(Int)

    /// One sentence naming the likely cause, written to be SPOKEN by Siri as
    /// well as read on a settings row. Deliberately distinct per shape: two
    /// shapes that speak the same sentence are the same collapse in new
    /// clothes (bar 56-U-C). No leading "Hermes" — the callers supply that.
    var spokenDetail: String {
        switch self {
        case .noAnswer:
            "The host didn't answer — it may be asleep, or you may be off the tailnet."
        case .refused:
            "The address answered but nothing is listening on that port — Hermes may not be running."
        case .hostNotFound:
            "That address didn't resolve — check that Tailscale is up."
        case .deviceOffline:
            "This device has no network connection."
        case .connectionLost:
            "The connection dropped mid-request — check Wi-Fi or the VPN."
        case .blockedByATS:
            "App Transport Security blocked that address — only tailnet addresses are allowed."
        case .notConfigured(let reason):
            reason
        case .other(let code):
            "The connection failed (error \(code)) — check that Hermes is running and the tailnet is up."
        }
    }
}

/// What one bounded reachability probe concluded.
///
/// **`reachable` means the host ANSWERED, whatever it answered.** A 401, a 404
/// and a 500 are all proof that the network path, the tailnet and the listener
/// are alive — the only thing this type is asked to decide. Reading a status
/// code as "unreachable" would re-break #56 in the other direction (bar
/// 56-U-E), and status interpretation already has an owner in
/// `ServerProbeResult.classify`.
enum HostReachabilityVerdict: Equatable, Sendable {
    case reachable(statusCode: Int)
    case unreachable(HostReachabilityFailure)
}

/// The shared, bounded "can we reach this host at all?" probe.
///
/// **Why a preflight rather than better error classification (#56).** The
/// chat plane's streaming request is stamped at 300s
/// (`SessionsHermesClient.streamingRequestTimeout`) because an SSE turn
/// legitimately runs for minutes. The Ask-Hermes intent answers Siri at 25s.
/// So against a black hole the stream produces no error at all inside the
/// intent's window, and no amount of classification can help: the intent has
/// already said "still working" and iOS has reaped the launch. Shortening the
/// streaming budget is the trap #145's own comment names — it would kill live
/// turns and present as a network bug. A separate, short, one-round-trip probe
/// is the only thing that fits.
///
/// **Why it cannot mislabel a slow turn.** Connect time and generation time are
/// independent: a Hermes that will think for two minutes still completes the
/// TCP handshake and answers `/v1/models` in milliseconds. Slowness lives in
/// the run, not the socket.
enum HostReachability {

    /// The probe's ceiling. Small on purpose — it is spent out of the caller's
    /// budget, never on top of it (bar 56-U-F), and a host that needs more
    /// than four seconds to complete a handshake is not one a Siri turn can
    /// wait for anyway.
    static let preflightBudget: Duration = .seconds(4)

    /// The cheapest route that proves the Sessions API is answering. `/v1/models`
    /// is on the verified `:8642` table and returns a static list, so its
    /// latency measures the path rather than the agent.
    static let probePath = "/v1/models"

    /// `URLError` → the shape that has its own remedy.
    ///
    /// `.timedOut` maps to `.noAnswer` here, which is NOT in tension with
    /// `SessionsHermesClient.isUnreachableError` deliberately excluding it:
    /// that predicate decides whether a turn may be silently re-sent from the
    /// offline outbox, where an ambiguous timeout could double-send a
    /// committed run (#240). This one only decides what to TELL the user, and
    /// a timeout is the single most informative shape there is — it is what a
    /// dropped-packet tailnet looks like.
    nonisolated static func classify(_ code: URLError.Code) -> HostReachabilityFailure {
        switch code {
        case .timedOut:
            return .noAnswer
        case .cannotConnectToHost:
            return .refused
        case .cannotFindHost, .dnsLookupFailed:
            return .hostNotFound
        case .notConnectedToInternet, .internationalRoamingOff, .dataNotAllowed:
            return .deviceOffline
        case .networkConnectionLost:
            return .connectionLost
        case .appTransportSecurityRequiresSecureConnection:
            return .blockedByATS
        default:
            return .other(code.rawValue)
        }
    }

    /// One round trip against `baseURL`, bounded by `timeout`.
    ///
    /// Never throws and never retries: a second attempt would double the worst
    /// case for no new information, and the caller's budget is the point.
    nonisolated static func probe(
        baseURL: String,
        apiKey: String,
        session: URLSession = makeProbeSession(),
        timeout: Duration = preflightBudget
    ) async -> HostReachabilityVerdict {
        var normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return .unreachable(.notConfigured("No Hermes gateway URL is set — add one in Settings under Uplink."))
        }
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard let url = URL(string: normalized + probePath) else {
            return .unreachable(.notConfigured("The Hermes gateway URL isn't a valid address."))
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Self.timeInterval(timeout)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                // Answered, but not over HTTP. Something is listening, so this
                // is emphatically not "unreachable" in the sense that matters —
                // but there is no status to report, so name it honestly.
                return .unreachable(.other(URLError.Code.badServerResponse.rawValue))
            }
            return .reachable(statusCode: http.statusCode)
        } catch let error as URLError {
            return .unreachable(classify(error.code))
        } catch {
            return .unreachable(.other(URLError.Code.unknown.rawValue))
        }
    }

    /// A session that cannot outlive the probe. Deliberately NOT
    /// `URLSession.shared` — its `timeoutIntervalForResource` is seven days,
    /// the knob that makes a wedge permanent (#145 Part A) — and deliberately
    /// not the chat plane's session either, whose one-hour resource ceiling
    /// exists for SSE runs this probe must never inherit.
    nonisolated static func makeProbeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeInterval(preflightBudget)
        configuration.timeoutIntervalForResource = timeInterval(preflightBudget)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// `Duration` is the currency of the intent's budget arithmetic;
    /// `URLRequest` speaks `TimeInterval`. One conversion, in one place.
    nonisolated static func timeInterval(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}

import Foundation

/// The Connect Host probe ladder's vocabulary (#309 Lane B, bar 309-B3).
///
/// **The design shows three named checks — "Address reachable", "Checking the
/// key", "Confirming it's a Hermes gateway" — so that a failure can point at
/// the one that broke rather than at "failed".** That promise is only worth
/// making if each verdict is a REAL discrimination, which is why this enum has
/// a `notConcluded` case alongside `failed`: one request cannot always answer
/// all three questions, and printing a green tick for a rung the request never
/// tested is exactly the theater the bar forbids.
///
/// Read the cases as answers to "what do we KNOW about this rung?":
/// - `pending` — the request is in flight; the design renders "…".
/// - `passed(detail)` — measured, with the measurement ("18MS", "14 SEEN").
/// - `failed(detail)` — measured, and it is the guilty rung ("TIMED OUT").
/// - `notReached` — an EARLIER rung died, so this one never got a chance.
/// - `notConcluded` — the request happened but could not test this rung. A
///   server that answers 200 without looking at the `Authorization` header has
///   not accepted the key; it has ignored it.
enum HostCheckVerdict: Equatable, Sendable {
    case pending
    case passed(String)
    case failed(String)
    case notReached
    case notConcluded

    /// The short right-hand label the design puts against each check row.
    var detailLabel: String {
        switch self {
        case .pending: "…"
        case .passed(let detail): detail
        case .failed(let detail): detail
        case .notReached: "NOT REACHED"
        case .notConcluded: "—"
        }
    }

    var isPassed: Bool {
        if case .passed = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// The three rows the checking card and every failure card render.
struct HostProbeLadder: Equatable, Sendable {
    var reachable: HostCheckVerdict
    var keyAccepted: HostCheckVerdict
    var hermesGateway: HostCheckVerdict

    /// What the card shows the instant the check starts: the first rung is in
    /// flight, and the two below it are honestly blank rather than optimistic.
    static let running = HostProbeLadder(
        reachable: .pending,
        keyAccepted: .notConcluded,
        hermesGateway: .notConcluded
    )
}

/// What ONE authenticated probe of a candidate host concluded.
///
/// Deliberately four cases and not a `Result`: the three failure shapes get
/// different screens (design B4/B5/B6), different guilty fields, and different
/// remedies, and collapsing them to "it didn't work" is the state-vocabulary
/// failure #180 exists to stop.
enum HostProbeOutcome: Equatable, Sendable {
    /// Everything answered: reachable, the key was taken, and the body decoded
    /// as a Hermes model catalog. `modelsSeen` feeds the card's "MODELS SEEN n".
    case connected(latencyMilliseconds: Int, modelsSeen: Int)
    /// Nothing answered at that address — transport failure or timeout.
    case noAnswer(detail: String)
    /// The host answered, and then refused this key (401/403).
    case keyRefused(latencyMilliseconds: Int)
    /// Something is listening there, but it is not a Hermes gateway — a 2xx
    /// whose body is not a model catalog, or any other non-2xx status.
    ///
    /// **No status code rides this case on purpose.** The design's own note on
    /// B6: *names the suspect character — the port — rather than quoting an
    /// HTTP code at a human.* A `404` in the ladder would be a number the
    /// reader cannot act on; "WRONG SHAPE" plus "try :8642" is the actionable
    /// half of the same fact.
    case notHermes(latencyMilliseconds: Int)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// Nothing came back. The retry verb differs — "TRY AGAIN" for an address
    /// that never answered, "CHECK AGAIN" once something did.
    var isNoAnswer: Bool {
        if case .noAnswer = self { return true }
        return false
    }

    /// The measured round trip, when there was one. `nil` means nothing came
    /// back at all — the one case where the app has no latency to report and
    /// must not invent one (#45's real-data-only rule).
    var latencyMilliseconds: Int? {
        switch self {
        case .connected(let ms, _), .keyRefused(let ms), .notHermes(let ms): ms
        case .noAnswer: nil
        }
    }

    /// The ladder as the failure cards render it.
    var ladder: HostProbeLadder {
        switch self {
        case .connected(let ms, let models):
            HostProbeLadder(
                reachable: .passed("\(ms)MS"),
                keyAccepted: .passed("ACCEPTED"),
                hermesGateway: .passed("\(models) SEEN")
            )
        case .noAnswer(let detail):
            // Only the first rung has a verdict — the other two never ran, and
            // "NOT REACHED" says that instead of implying they failed.
            HostProbeLadder(
                reachable: .failed(detail),
                keyAccepted: .notReached,
                hermesGateway: .notReached
            )
        case .keyRefused(let ms):
            // The shape check is NOT concluded: a 401 tells us something is
            // guarding that port, not that it is Hermes.
            HostProbeLadder(
                reachable: .passed("\(ms)MS"),
                keyAccepted: .failed("REFUSED"),
                hermesGateway: .notConcluded
            )
        case .notHermes(let ms):
            // The KEY rung is not concluded either — a server that answers 200
            // without reading the bearer never tested it, and a 404 tells us
            // nothing about credentials.
            HostProbeLadder(
                reachable: .passed("\(ms)MS"),
                keyAccepted: .notConcluded,
                hermesGateway: .failed("WRONG SHAPE")
            )
        }
    }

    /// Which field the failure card re-offers. `nil` on success — and note
    /// that "no answer" blames the ADDRESS while "key refused" blames the KEY,
    /// which is the whole reason the ladder exists.
    var guiltyField: ConnectHostField? {
        switch self {
        case .connected: nil
        case .noAnswer: .gatewayURL
        case .keyRefused: .apiKey
        case .notHermes: .gatewayURL
        }
    }
}

/// The two values a host connection is made of. Used to flag exactly one field
/// on a failure — design B1's "only the guilty field is flagged".
enum ConnectHostField: Equatable, Sendable {
    case gatewayURL
    case apiKey
}

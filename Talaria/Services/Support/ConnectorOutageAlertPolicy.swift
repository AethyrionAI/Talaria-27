import Foundation

/// #113: decides when repeated sensor-drain retry-exhaustion becomes a
/// user-visible inbox alert — and when that alert clears.
///
/// The dead-connector shape: the relay stays up and 202-busies every ingest,
/// the app maps that to `.retry`, exhausts the busy ladder, defers, and the
/// backlog piles up with no surface beyond the diagnostics panel string
/// (#15). Three consecutive drain cycles ending in retry-exhaustion is that
/// shape, not a transient — raise ONE alert. Only a real delivery proves the
/// connector alive again, so only a delivery clears it.
///
/// Pure state machine: no clocks, no I/O, no references — callers feed drain
/// outcomes in and act on the returned effect. That keeps the
/// trigger/dedupe/clear rules unit-testable without a drain harness.
struct ConnectorOutageAlertPolicy {
    /// Consecutive retry-exhausted drain cycles before the alert raises.
    static let consecutiveExhaustionThreshold = 3

    /// What a finished drain cycle proved about the connector.
    enum DrainCycleOutcome {
        /// At least one upload delivered — the connector is alive.
        case delivered
        /// Nothing delivered and at least one phase gave up after the
        /// connector-busy retry ladder (the 202 "retry" trap).
        case retryExhausted
        /// Anything else: transport failure, rejection-only, isolation stall.
        /// Breaks the exhaustion streak (the signature is CONSECUTIVE
        /// exhaustion) without proving the connector alive.
        case inconclusive
    }

    /// What the caller should do after recording an outcome.
    enum Effect: Equatable {
        case none
        /// Enqueue the connector-down inbox alert (fires at most once per outage).
        case raiseAlert
        /// Remove the alert — a delivery proved the connector alive.
        case clearAlert
    }

    private(set) var consecutiveExhaustedCycles = 0
    /// Dedupe: while true, further exhausted cycles never re-raise.
    private(set) var alertActive = false

    mutating func record(_ outcome: DrainCycleOutcome) -> Effect {
        switch outcome {
        case .delivered:
            consecutiveExhaustedCycles = 0
            guard alertActive else { return .none }
            alertActive = false
            return .clearAlert
        case .retryExhausted:
            consecutiveExhaustedCycles += 1
            guard consecutiveExhaustedCycles >= Self.consecutiveExhaustionThreshold, !alertActive else {
                return .none
            }
            alertActive = true
            return .raiseAlert
        case .inconclusive:
            consecutiveExhaustedCycles = 0
            return .none
        }
    }
}

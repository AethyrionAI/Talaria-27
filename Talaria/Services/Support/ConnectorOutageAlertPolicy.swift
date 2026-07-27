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
///
/// Since #117 the same exhaustion streak also drives the CROSS-CYCLE drain
/// backoff: `recommendedCrossCycleBackoff` converts the streak into how long
/// the next drain cycle should rest. One streak, two consumers — the alert
/// threshold and the backoff ladder never disagree about what "consecutive
/// exhaustion" means.
struct ConnectorOutageAlertPolicy {
    /// Consecutive retry-exhausted drain cycles before the alert raises.
    static let consecutiveExhaustionThreshold = 3

    // MARK: - Cross-cycle backoff (#117)

    /// First rest after a single exhausted cycle. Deliberately short: early
    /// in an outage the natural sensor cadence already spaces cycles ~200s
    /// apart, so a 30s gate is invisible there — it only bites once the
    /// backlog is continuously non-empty and enqueue-driven triggers would
    /// otherwise restart an exhausted cycle back-to-back (the shape the
    /// 2026-07-25 device pass measured at 126% of healthy baseline).
    static let crossCycleBackoffBase: TimeInterval = 30
    /// Ceiling on the rest between cycles during a sustained outage. 300s
    /// keeps the worst-case failing burst — location + health ladders both
    /// exhausting, 7 POSTs over ~20s — near 1.3 req/min, well below the
    /// ~3.5 req/min healthy-baseline drain rate, while the connector is
    /// still probed at least every 5 minutes even with no external wake
    /// (foreground/launch lift the gate earlier).
    static let crossCycleBackoffCeiling: TimeInterval = 300

    /// How long the NEXT drain cycle should rest given the outcomes recorded
    /// so far: 0 after a delivery or an inconclusive cycle (only the
    /// dead-connector shape escalates — #117), else doubling per consecutive
    /// exhausted cycle from the base up to the ceiling. Pure like the rest
    /// of the policy: a duration, not an instant — the caller owns the clock.
    var recommendedCrossCycleBackoff: TimeInterval {
        guard consecutiveExhaustedCycles > 0 else { return 0 }
        // Four doublings already lift the base past the ceiling; clamping
        // the exponent keeps the shift safe for arbitrarily long outages.
        let doublings = min(consecutiveExhaustedCycles - 1, 4)
        return min(Self.crossCycleBackoffCeiling, Self.crossCycleBackoffBase * TimeInterval(1 << doublings))
    }

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

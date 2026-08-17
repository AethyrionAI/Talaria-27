import Foundation
import Testing
@testable import Talaria

// #113: the trigger/dedupe/clear rules for the connector-down inbox alert,
// tested as the pure decision function they are — no drain harness, no I/O.

@Suite("ConnectorOutageAlertPolicy")
struct ConnectorOutageAlertPolicyTests {

    @Test("Alert raises on the 3rd consecutive retry-exhausted cycle, not before")
    func raisesAtThreshold() {
        var policy = ConnectorOutageAlertPolicy()
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .raiseAlert)
    }

    @Test("Dedupe: the outage keeps exhausting but the alert fires exactly once")
    func raisesOnlyOncePerOutage() {
        var policy = ConnectorOutageAlertPolicy()
        for _ in 0..<3 { _ = policy.record(.retryExhausted) }
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.alertActive)
    }

    @Test("A delivery before the threshold resets the streak")
    func deliveryResetsStreak() {
        var policy = ConnectorOutageAlertPolicy()
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.delivered) == .none)  // nothing raised yet — nothing to clear
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .raiseAlert)
    }

    @Test("An inconclusive cycle breaks the streak — the signature is CONSECUTIVE exhaustion")
    func inconclusiveBreaksStreak() {
        var policy = ConnectorOutageAlertPolicy()
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.inconclusive) == .none)
        #expect(policy.record(.retryExhausted) == .none)  // streak restarted at 1
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .raiseAlert)
    }

    @Test("Only a delivery clears an active alert — inconclusive cycles never do")
    func clearsOnlyOnDelivery() {
        var policy = ConnectorOutageAlertPolicy()
        for _ in 0..<3 { _ = policy.record(.retryExhausted) }
        #expect(policy.alertActive)
        #expect(policy.record(.inconclusive) == .none)
        #expect(policy.alertActive)
        #expect(policy.record(.delivered) == .clearAlert)
        #expect(!policy.alertActive)
        #expect(policy.record(.delivered) == .none)  // clear fires once
    }

    @Test("After a clear, a fresh outage must re-accumulate the full streak to re-raise")
    func reRaisesAfterRecovery() {
        var policy = ConnectorOutageAlertPolicy()
        for _ in 0..<3 { _ = policy.record(.retryExhausted) }
        #expect(policy.record(.delivered) == .clearAlert)
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .none)
        #expect(policy.record(.retryExhausted) == .raiseAlert)
    }

    @Test("Threshold constant matches the dispatched N=3")
    func thresholdIsThree() {
        #expect(ConnectorOutageAlertPolicy.consecutiveExhaustionThreshold == 3)
    }

    // MARK: - Cross-cycle backoff recommendation (#117)

    @Test("#117: the recommended rest doubles per consecutive exhausted cycle, strictly, up to the ceiling")
    func crossCycleRestEscalatesStrictlyToTheCeiling() {
        var policy = ConnectorOutageAlertPolicy()
        #expect(policy.recommendedCrossCycleBackoff == 0)  // no evidence, no gate

        var rests: [TimeInterval] = []
        for _ in 0..<8 {
            _ = policy.record(.retryExhausted)
            rests.append(policy.recommendedCrossCycleBackoff)
        }

        #expect(rests.first == ConnectorOutageAlertPolicy.crossCycleBackoffBase)
        #expect(rests.last == ConnectorOutageAlertPolicy.crossCycleBackoffCeiling)
        for (previous, next) in zip(rests, rests.dropFirst()) {
            #expect(next <= ConnectorOutageAlertPolicy.crossCycleBackoffCeiling)
            if previous < ConnectorOutageAlertPolicy.crossCycleBackoffCeiling {
                #expect(next > previous)  // strictly increasing below the ceiling
            } else {
                #expect(next == ConnectorOutageAlertPolicy.crossCycleBackoffCeiling)  // pinned at it
            }
        }
    }

    @Test("#117: a delivery zeroes the recommended rest; a fresh outage restarts at the base")
    func deliveryResetsCrossCycleRestToBaseline() {
        var policy = ConnectorOutageAlertPolicy()
        for _ in 0..<4 { _ = policy.record(.retryExhausted) }
        #expect(policy.recommendedCrossCycleBackoff > ConnectorOutageAlertPolicy.crossCycleBackoffBase)

        _ = policy.record(.delivered)
        #expect(policy.recommendedCrossCycleBackoff == 0)

        _ = policy.record(.retryExhausted)
        #expect(policy.recommendedCrossCycleBackoff == ConnectorOutageAlertPolicy.crossCycleBackoffBase)
    }

    @Test("#117: inconclusive cycles never escalate — only the dead-connector shape does")
    func inconclusiveNeverEscalatesCrossCycleRest() {
        var policy = ConnectorOutageAlertPolicy()
        #expect(policy.record(.inconclusive) == .none)
        #expect(policy.recommendedCrossCycleBackoff == 0)

        for _ in 0..<3 { _ = policy.record(.retryExhausted) }
        _ = policy.record(.inconclusive)
        // The streak is CONSECUTIVE exhaustion (the #113 definition, reused
        // verbatim by #117): an inconclusive cycle breaks it, so the gate
        // drops rather than escalating on mixed evidence.
        #expect(policy.recommendedCrossCycleBackoff == 0)
    }
}


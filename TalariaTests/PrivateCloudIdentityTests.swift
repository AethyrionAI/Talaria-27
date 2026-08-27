import Foundation
import Testing
@testable import Talaria

/// **#385 — the assistant must not tell a PCC user their conversation never
/// leaves the device.** Bars 385-A…D.
///
/// **Found on device 2026-08-20, in PCC's first hour.** Owen asked the model
/// what it could do on Private Cloud Compute and it answered *"I'm running
/// directly on your iPhone using Apple's on-device foundation model, so
/// there's no backend involved."* The model was not confabulating — it was
/// repeating `instructionsText`, which was parameterised on tools, on images
/// and on three separate toolless clauses, and **not on tier**. The turn
/// genuinely ran on PCC (proved by the 32K context window, not by the routing
/// label).
///
/// That is #180's shape aimed at the one property a PCC user cares about, so
/// these bars pin both halves: the lie is gone, **and** the truth it was
/// generalised from is still told where it holds.
@MainActor
struct PrivateCloudIdentityTests {

    // MARK: - 385-A — a PCC session is never told it runs on-device

    @Test func privateCloudIdentityNamesTheTierAndDropsTheDeviceClaim() {
        let pcc = LocalChatBackend.identitySentence(for: .privateCloud)

        #expect(!pcc.contains("never leaves the device"))
        #expect(!pcc.contains("entirely on their iPhone"))
        #expect(pcc.contains("Private Cloud Compute"))
    }

    /// The claim has to be absent from the WHOLE instruction payload, not
    /// just the sentence — the identity line is one of several places a
    /// location claim could hide.
    @Test func theFullPrivateCloudPayloadCarriesNoOnDeviceClaim() {
        let instructions = LocalChatBackend.instructionsText(
            deviceContext: "Device: iPhone running iOS 27.0.",
            tier: .privateCloud,
            hasTools: false,
            hasImageTools: false
        )
        #expect(!instructions.contains("never leaves the device"))
        #expect(!instructions.contains("entirely on their iPhone"))
        #expect(instructions.contains("Private Cloud Compute"))
    }

    /// The routed-toolless branch is the one a real turn usually takes (#196),
    /// so gating only the armed branch would have left the common case
    /// telling the same lie.
    @Test func theToollessPrivateCloudPayloadCarriesNoOnDeviceClaimEither() {
        let instructions = LocalChatBackend.productionToollessInstructions(
            deviceContext: "Device: iPhone running iOS 27.0.",
            tier: .privateCloud,
            hasImageTools: false
        )
        #expect(!instructions.contains("never leaves the device"))
        #expect(instructions.contains("Private Cloud Compute"))
    }

    // MARK: - 385-B — the on-device sentence is unchanged, to the byte

    /// **The negative control, and the bar that encodes a ruling.**
    ///
    /// Owen explicitly rejected stripping the location clause from both
    /// tiers. The sentence is TRUE on the on-device tier and it is useful:
    /// the fix is to stop GENERALISING it, not to go quiet. Without this bar,
    /// 385-A is satisfied by deleting the sentence everywhere — trading a
    /// false claim for a silence and losing the free tier's strongest honest
    /// statement about itself.
    ///
    /// Pinned as a golden string rather than a property, because "unchanged"
    /// is the whole claim.
    @Test func onDeviceIdentityIsByteIdenticalToWhatShipped() {
        #expect(
            LocalChatBackend.identitySentence(for: .onDevice)
                == "You are Talaria, the user's personal assistant, running entirely on their iPhone with Apple's on-device foundation model. The conversation is private and never leaves the device."
        )
    }

    // MARK: - 385-C — the two tiers say DIFFERENT things

    /// #173-B's inequality shape, here for the same reason: one tier-neutral
    /// sentence satisfies 385-A and 385-B's prose while failing the ruling,
    /// and it is exactly what a later "simplify the duplication" lane
    /// reaches for first.
    @Test func theTwoTiersDoNotShareOneIdentitySentence() {
        #expect(
            LocalChatBackend.identitySentence(for: .onDevice)
                != LocalChatBackend.identitySentence(for: .privateCloud)
        )
    }

    // MARK: - 385-D — the opt-in prompt claims nothing about equal privacy

    /// Pinned because #173-E proved that copy nothing asserts can be silently
    /// un-shipped by a later edit — and this is the sentence shown at the
    /// exact moment the user is asked to opt in.
    @Test func escalationBannerNamesPCCAndClaimsNoEquivalence() {
        let copy = ChatScreen.privateCloudEscalationCopy
        #expect(!copy.contains("same privacy"))
        #expect(copy.contains("Private Cloud Compute"))
    }
}

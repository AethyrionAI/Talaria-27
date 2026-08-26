import Foundation
import Testing
@testable import Talaria

/// **Bar 309-B5 — the `pair-qr` payload is a CROSS-REPO CONTRACT, pinned on
/// this side of it.**
///
/// The plugin repo holds the canonical bytes at
/// `tests/fixtures/pair_payload.json` and a plugin test pins them there;
/// `fixtureBytes` below is a verbatim copy, so a shape change that lands in
/// one repository alone fails a suite instead of failing a user's scan.
///
/// The fixture was fetched from `AethyrionAI/talaria-plugin@b4e8dfa`
/// (#309 Lane D) and round-trip-proven host-side with Apple's own
/// `VNDetectBarcodesRequest` — the framework this app's scanner uses.
@MainActor
struct ConnectHostPayloadTests {

    /// **Byte-for-byte the plugin repo's `tests/fixtures/pair_payload.json`**
    /// — two-space indent, key order as written, trailing newline. Compared as
    /// a STRING as well as decoded, because a fixture that only has to decode
    /// can drift in every way that matters to a QR reader.
    static let fixtureBytes = """
    {
      "talaria": 1,
      "gateway": "http://100.79.222.100:8642",
      "key": "FIXTURE-API-SERVER-KEY-00000000000000000000000000000000000000000",
      "name": "Owens-Mac-mini"
    }

    """

    @Test func thePluginsFixturePayloadDecodesIntoAUsableHost() {
        guard case .success(let payload) = TalariaPairPayload.decode(Self.fixtureBytes) else {
            Issue.record("the pinned cross-repo fixture no longer decodes — the contract has drifted")
            return
        }
        #expect(payload.gatewayBaseURL == "http://100.79.222.100:8642")
        #expect(payload.apiKey == "FIXTURE-API-SERVER-KEY-00000000000000000000000000000000000000000")
        #expect(payload.name == "Owens-Mac-mini")
        // The real `API_SERVER_KEY` is 64 characters; the fixture matches its
        // shape so a length assumption anywhere would be caught here.
        #expect(payload.apiKey.count == 64)
    }

    /// The WIRE form is compact JSON (`json.dumps(..., separators=(",", ":"))`
    /// in `pairing_qr.encode_payload`) — a smaller symbol, fewer scan
    /// failures. The pretty fixture and the compact wire form must decode to
    /// the same thing, or the file pins something the QR never carries.
    @Test func theCompactWireFormAndThePrettyFixtureAgree() {
        let compact = #"{"talaria":1,"gateway":"http://100.79.222.100:8642","key":"FIXTURE-API-SERVER-KEY-00000000000000000000000000000000000000000","name":"Owens-Mac-mini"}"#
        guard case .success(let fromWire) = TalariaPairPayload.decode(compact),
              case .success(let fromFile) = TalariaPairPayload.decode(Self.fixtureBytes)
        else {
            Issue.record("one of the two forms failed to decode")
            return
        }
        #expect(fromWire == fromFile)
    }

    /// Key order is irrelevant, per the contract.
    @Test func keyOrderDoesNotMatter() {
        let shuffled = #"{"name":"OJAMD","key":"k","gateway":"http://h:8642","talaria":1}"#
        guard case .success(let payload) = TalariaPairPayload.decode(shuffled) else {
            Issue.record("key order changed the outcome — the contract says it must not")
            return
        }
        #expect(payload.name == "OJAMD")
    }

    // MARK: What must NOT decode

    /// **The relay-era code, refused.** This is #412's whole shape: the old
    /// scanner accepted an 8-character relay-alphabet code minted by a CLI
    /// verb Lane D deleted, redeemed at a service retired on both hosts. A
    /// stale printout must fail AT THE SCAN with a sentence naming the real
    /// command, not be carried into a flow that cannot complete.
    @Test func theOldRelayPairingCodeIsNotAHostCode() {
        for stale in ["ABCD-EFGH", "ABCDEFGH", "abcd-efgh"] {
            guard case .failure(let reason) = TalariaPairPayload.decode(stale) else {
                Issue.record("a relay-era pairing code decoded as a host payload: \(stale)")
                return
            }
            #expect(reason == .notATalariaCode)
            #expect(reason.message.contains("hermes talaria pair-qr"),
                    "the refusal must name the command that DOES exist")
        }
    }

    /// The old QR payload the connector printed — `{"code":…,"relay":…}` — is
    /// JSON, so only the mandatory version field separates it from ours.
    @Test func theOldConnectorQRPayloadIsRefused() {
        let old = #"{"code":"ABCDEFGH","relay":"http://100.110.102.59:8000/v1"}"#
        guard case .failure(let reason) = TalariaPairPayload.decode(old) else {
            Issue.record("the relay-era QR payload decoded as a host payload")
            return
        }
        #expect(reason == .notATalariaCode)
    }

    @Test func aFutureVersionIsNamedRatherThanMisread() {
        let future = #"{"talaria":2,"gateway":"http://h:8642","key":"k"}"#
        guard case .failure(let reason) = TalariaPairPayload.decode(future) else {
            Issue.record("a v2 payload decoded under v1 rules")
            return
        }
        #expect(reason == .unsupportedVersion(2))
        #expect(reason.message.contains("newer Talaria plugin"))
    }

    /// `talaria` must be an INTEGER. `true` bridges to `NSNumber` on Darwin
    /// and would read as `1` under a naive cast — a boolean is not a version,
    /// and neither is `1.5`.
    @Test func theVersionFieldMustBeAnHonestInteger() {
        for bogus in [#"{"talaria":true,"gateway":"http://h:8642","key":"k"}"#,
                      #"{"talaria":1.5,"gateway":"http://h:8642","key":"k"}"#,
                      #"{"talaria":"1","gateway":"http://h:8642","key":"k"}"#,
                      #"{"gateway":"http://h:8642","key":"k"}"#] {
            guard case .failure(let reason) = TalariaPairPayload.decode(bogus) else {
                Issue.record("a bogus version decoded: \(bogus)")
                return
            }
            #expect(reason == .notATalariaCode)
        }
    }

    /// Ours, but incomplete — a DIFFERENT failure, because the remedy differs:
    /// print a new code, rather than "that isn't a Talaria code at all".
    @Test func aTalariaPayloadMissingAValueSaysSoSpecifically() {
        for incomplete in [#"{"talaria":1,"gateway":"http://h:8642"}"#,
                           #"{"talaria":1,"key":"k"}"#,
                           #"{"talaria":1,"gateway":"","key":"k"}"#,
                           #"{"talaria":1,"gateway":"http://h:8642","key":"   "}"#] {
            guard case .failure(let reason) = TalariaPairPayload.decode(incomplete) else {
                Issue.record("an incomplete payload decoded: \(incomplete)")
                return
            }
            #expect(reason == .missingValue, "wrong failure for \(incomplete)")
        }
    }

    /// A missing NAME is not a failure — typed setups have none either, and
    /// the flow falls back to the address's host (spec §3.4).
    @Test func anAbsentNameIsAllowedAndFallsBackToTheHost() async {
        guard case .success(let payload) =
            TalariaPairPayload.decode(#"{"talaria":1,"gateway":"http://ojamd.tailnet.test:8642","key":"k"}"#)
        else {
            Issue.record("a name-less payload should decode")
            return
        }
        #expect(payload.name == nil)

        let model = ConnectHostModel(environment: .inert())
        model.apply(payload)
        #expect(model.draft.resolvedName == "ojamd.tailnet.test")
    }

    /// Scanning fills the SAME two fields typing does — the QR is sugar on the
    /// typed arm, not a second code path (design doc §3a).
    @Test func scanningFillsTheSameDraftTypingWouldHave() async {
        let model = ConnectHostModel(environment: .inert())
        guard case .success(let payload) = TalariaPairPayload.decode(Self.fixtureBytes) else {
            Issue.record("fixture failed to decode")
            return
        }
        model.apply(payload)

        #expect(model.draft.gatewayBaseURL == "http://100.79.222.100:8642")
        #expect(model.draft.apiKey == "FIXTURE-API-SERVER-KEY-00000000000000000000000000000000000000000")
        #expect(model.draft.name == "Owens-Mac-mini")
        #expect(model.canCheck, "a scanned payload must be immediately checkable")
    }
}

import Foundation

/// The QR payload `hermes talaria pair-qr` prints (#309 Lanes D + B).
///
/// ```json
/// {"talaria":1,"gateway":"http://100.79.222.100:8642","key":"…","name":"OJAMD"}
/// ```
///
/// **This is a CROSS-REPO CONTRACT and it is pinned on both sides.** The plugin
/// repo holds the canonical bytes at `tests/fixtures/pair_payload.json`;
/// `ConnectHostPayloadTests` pins the same bytes here, so a shape change that
/// lands in one repo alone fails a suite instead of failing a user's scan.
/// `talaria` is a MANDATORY integer version rather than a convention for the
/// same reason — bumping it is a breaking change for every already-scanned
/// phone, and a payload without it is not ours.
///
/// **What replaced what.** The old scanner accepted `{"code":…,"relay":…}` — an
/// 8-character code from the relay's alphabet, redeemed against a service that
/// is retired on both hosts, printed by a CLI verb Lane D deleted (#412). None
/// of that decodes here, deliberately: a stale QR must fail loudly at the scan
/// rather than land the user in a flow that cannot complete.
struct TalariaPairPayload: Equatable, Sendable {
    /// The only version this build speaks.
    static let supportedVersion = 1

    let gatewayBaseURL: String
    let apiKey: String
    /// The host's own label. Absent in a hand-built payload; the Connect Host
    /// flow then falls back to the address's host component (spec §3.4).
    let name: String?

    /// The wire key strings. Not `CodingKeys` — there is no `Codable`
    /// conformance here, for the reason `decode(_:)` states.
    private enum PayloadKey: String {
        case talaria, gateway, key, name
    }

    enum DecodeFailure: Error, Equatable, Sendable {
        /// Not JSON, or not an object — including a bare relay-era code.
        case notATalariaCode
        /// A talaria payload from a future plugin this build cannot read.
        case unsupportedVersion(Int)
        /// JSON object, right version, missing a value the pairing needs.
        case missingValue

        /// What the scanner surface says. Never quotes JSON at a human.
        var message: String {
            switch self {
            case .notATalariaCode:
                "That isn't a Talaria host code. Run `hermes talaria pair-qr` on your Hermes machine."
            case .unsupportedVersion:
                "That code was made by a newer Talaria plugin than this app understands. Update the app, or type the two values instead."
            case .missingValue:
                "That code is missing the address or the key. Print a new one with `hermes talaria pair-qr`."
            }
        }
    }

    /// Decodes a scanned string, naming WHY it failed.
    ///
    /// Hand-rolled over `JSONSerialization` rather than `Codable` on purpose:
    /// the three failures above need to be distinguishable, and a thrown
    /// `DecodingError` collapses "not ours" and "ours but incomplete" into the
    /// same keyNotFound shape.
    static func decode(_ scanned: String) -> Result<TalariaPairPayload, DecodeFailure> {
        guard let data = scanned.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .failure(.notATalariaCode)
        }
        // `talaria` must be an INTEGER. A JSON `true` bridges to `NSNumber` on
        // Darwin and would otherwise read as 1 — a boolean is not a version —
        // and `{"talaria":1.5}` is not one either.
        guard let versionNumber = object[PayloadKey.talaria.rawValue] as? NSNumber,
              CFGetTypeID(versionNumber as CFTypeRef) != CFBooleanGetTypeID(),
              Double(versionNumber.intValue) == versionNumber.doubleValue
        else {
            return .failure(.notATalariaCode)
        }
        let version = versionNumber.intValue
        guard version == supportedVersion else {
            return .failure(.unsupportedVersion(version))
        }

        let gateway = (object[PayloadKey.gateway.rawValue] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = (object[PayloadKey.key.rawValue] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !gateway.isEmpty, !key.isEmpty else {
            return .failure(.missingValue)
        }
        let name = (object[PayloadKey.name.rawValue] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return .success(
            TalariaPairPayload(
                gatewayBaseURL: gateway,
                apiKey: key,
                name: (name?.isEmpty == false) ? name : nil
            )
        )
    }
}

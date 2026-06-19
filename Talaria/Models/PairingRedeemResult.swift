import Foundation

struct PairingRedeemResult: Hashable, Sendable {
    let configuration: PairedRelayConfiguration
    let state: AppSessionState
    let tokens: AuthTokens
}

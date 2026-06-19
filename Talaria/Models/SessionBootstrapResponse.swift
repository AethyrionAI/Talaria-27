import Foundation

struct SessionBootstrapResponse: Codable, Hashable, Sendable {
    let state: AppSessionState
    let tokens: AuthTokens
}

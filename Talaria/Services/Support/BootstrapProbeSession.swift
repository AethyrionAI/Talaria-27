import Foundation

/// #136: the launch/bootstrap-probe URLSession budget.
///
/// **Moved out of `RelayAPIClient` by #309 Lane C (bar C2), unchanged.** The
/// budget was never about the relay — it is about what a BLACK-HOLED host does
/// to a launch: Windows Firewall silently DROPS packets to listener-less
/// ports, so there is no TCP refusal and every request hangs the full timeout
/// (error -1001). The relay client happened to be the first probe-class caller
/// to need it; the gateway host probe is the next one, and the constants had to
/// outlive their first home.
///
/// Probe-class surfaces ONLY — never the chat path (`:8642` turns), SSE
/// streams, or any long transfer, whose semantics a 10 s resource timeout
/// would break.
enum BootstrapProbeSession {
    static let requestTimeout: TimeInterval = 5
    static let resourceTimeout: TimeInterval = 10

    static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}

import Testing
@testable import Talaria

/// **#377 — the Private Relay diagnostics row.**
///
/// The whole item is one honesty problem: iOS exposes no API for "is Private
/// Relay on", so the row either reasons from evidence that DISCRIMINATES the
/// condition or it says nothing. These pins are written against the bars
/// registered before the code, and most of them assert SILENCE — which is the
/// behaviour a row like this gets wrong.
struct PrivateRelayIndicatorTests {

    /// The one host shape the condition can bite: Tailscale's CGNAT literal,
    /// spoken to over cleartext HTTP. `:8642` is the surviving interceptable
    /// path after #352 (sensors deleted) and #375 (relay + shim retired).
    private let tailnetHTTP = "http://100.110.102.59:8642"

    // MARK: - 377-A: the discriminator

    /// **377-A.** All three legs present — cleartext, CGNAT literal, and a
    /// proxy-shaped gateway status — is the only way to name the condition.
    @Test func proxyShapedStatusOnCleartextTailnetHTTPNamesTheCondition() {
        #expect(PrivateRelayIndicator.verdict(
            baseURL: tailnetHTTP, failure: .unexpectedStatus(502)) == .indicated)
        #expect(PrivateRelayIndicator.verdict(
            baseURL: tailnetHTTP, failure: .unexpectedStatus(504)) == .indicated)
    }

    /// **377-A's negative controls — each breaks exactly ONE leg.** Without
    /// these the pin above proves only that the function can say yes.
    @Test func eachLegIsLoadBearing() {
        // Leg 1 broken: TLS. Private Relay proxies unencrypted app traffic
        // only, which is why the OTA install over `tailscale serve` works.
        #expect(PrivateRelayIndicator.verdict(
            baseURL: "https://100.110.102.59:8642", failure: .unexpectedStatus(502)) == nil)
        // Leg 2 broken: not a tailnet address.
        #expect(PrivateRelayIndicator.verdict(
            baseURL: "http://192.168.1.20:8642", failure: .unexpectedStatus(502)) == nil)
        // Leg 3 broken: the host answered with a status only a real server
        // sends. A 500 from Hermes is Hermes' problem, not a proxy's.
        #expect(PrivateRelayIndicator.verdict(
            baseURL: tailnetHTTP, failure: .unexpectedStatus(500)) == nil)
    }

    /// 503 is excluded on purpose: a real server says it while starting up or
    /// shedding load, so it does not discriminate an intermediary at all.
    @Test func onlyGatewayStatusesCountAsProxyShaped() {
        #expect(PrivateRelayIndicator.isProxyShaped(status: 502))
        #expect(PrivateRelayIndicator.isProxyShaped(status: 504))
        #expect(PrivateRelayIndicator.isProxyShaped(status: 503) == false)
        #expect(PrivateRelayIndicator.isProxyShaped(status: 500) == false)
        #expect(PrivateRelayIndicator.isProxyShaped(status: 200) == false)
    }

    /// The CGNAT range is `100.64.0.0/10` — the same range the ATS exception is
    /// scoped to (#166b). The boundary octets are the part a hand-written check
    /// gets wrong, so both edges and both misses are pinned.
    @Test func cgnatRangeIsExactlyOneSlashTen() {
        #expect(PrivateRelayIndicator.isTailnetCGNAT(host: "100.64.0.0"))
        #expect(PrivateRelayIndicator.isTailnetCGNAT(host: "100.127.255.255"))
        #expect(PrivateRelayIndicator.isTailnetCGNAT(host: "100.110.102.59"))
        #expect(PrivateRelayIndicator.isTailnetCGNAT(host: "100.63.255.255") == false)
        #expect(PrivateRelayIndicator.isTailnetCGNAT(host: "100.128.0.0") == false)
        #expect(PrivateRelayIndicator.isTailnetCGNAT(host: "10.0.0.1") == false)
        // A MagicDNS name is not a literal — and per #166b it has no ATS
        // exception, so it fails long before Private Relay is reached.
        #expect(PrivateRelayIndicator.isTailnetCGNAT(host: "owens-mac-mini.tail5663a6.ts.net") == false)
    }

    // MARK: - 377-B: a timeout does not get named

    /// **377-B.** #24e measured "30-second timeouts for the shim", so a timeout
    /// really is one of this condition's presentations — but it is equally what
    /// a powered-down host looks like, so it may not be diagnosed. The row
    /// states the configuration fact and offers Private Relay as ONE candidate.
    @Test func aTimeoutStatesTheExposureAndClaimsNothing() {
        let verdict = PrivateRelayIndicator.verdict(baseURL: tailnetHTTP, failure: .timedOut)
        #expect(verdict == .pathExposed)
        #expect(verdict != .indicated)
    }

    /// The two verdicts must not read alike: the weak one offers alternatives
    /// and the strong one asserts a source. A future copy edit that collapses
    /// them goes RED here.
    @Test func theWeakVerdictDoesNotReadLikeADiagnosis() throws {
        let weak = try #require(PrivateRelayIndicator.verdict(
            baseURL: tailnetHTTP, failure: .timedOut)).detail
        let strong = try #require(PrivateRelayIndicator.verdict(
            baseURL: tailnetHTTP, failure: .unexpectedStatus(502))).detail
        #expect(weak != strong)
        // The weak wording names other causes; the strong one names a source.
        #expect(weak.contains("others"))
        #expect(strong.contains("came from a proxy"))
        #expect(strong.contains("others") == false)
    }

    /// A timeout over TLS, or to a non-tailnet host, is not even exposed — the
    /// weak verdict is still gated on the path, not handed out on any failure.
    @Test func theWeakVerdictIsStillGatedOnThePath() {
        #expect(PrivateRelayIndicator.verdict(
            baseURL: "https://100.110.102.59:8642", failure: .timedOut) == nil)
        #expect(PrivateRelayIndicator.verdict(
            baseURL: "http://192.168.1.20:8642", failure: .timedOut) == nil)
    }

    // MARK: - 377-C: silence when there is nothing to say

    /// **377-C.** Refused and auth-rejected are ANSWERS — something on the path
    /// replied — which is not the proxy's black-hole shape. `hostNotFound` is
    /// DNS, and a CGNAT literal resolves nothing. `notConfigured` has no
    /// request to reason about at all.
    @Test func answersAndNonRequestsRenderNoRow() {
        #expect(PrivateRelayIndicator.verdict(baseURL: tailnetHTTP, failure: .refused) == nil)
        #expect(PrivateRelayIndicator.verdict(baseURL: tailnetHTTP, failure: .authRejected) == nil)
        #expect(PrivateRelayIndicator.verdict(baseURL: tailnetHTTP, failure: .hostNotFound) == nil)
        #expect(PrivateRelayIndicator.verdict(
            baseURL: tailnetHTTP, failure: .notConfigured("No base URL set.")) == nil)
    }

    /// Nothing to explain when the path works: the row is reached only from the
    /// FAILED arm of the Test Connection result, so a passing probe cannot
    /// produce one. Pinned at the path level, which is what the view consults.
    @Test func anUnparseableOrEmptyBaseURLIsNotAPath() {
        #expect(PrivateRelayIndicator.pathIsInterceptable(baseURL: "") == false)
        #expect(PrivateRelayIndicator.pathIsInterceptable(baseURL: "not a url") == false)
        #expect(PrivateRelayIndicator.pathIsInterceptable(baseURL: "100.110.102.59:8642") == false)
        // Whitespace is what a pasted URL actually arrives with.
        #expect(PrivateRelayIndicator.pathIsInterceptable(baseURL: "  \(tailnetHTTP)  "))
    }

    /// Scheme comparison is case-insensitive: `HTTP://` is still cleartext, and
    /// a check that missed it would silently drop the row for a user who typed
    /// the URL in caps.
    @Test func schemeMatchingIsCaseInsensitive() {
        #expect(PrivateRelayIndicator.pathIsInterceptable(baseURL: "HTTP://100.110.102.59:8642"))
    }
}

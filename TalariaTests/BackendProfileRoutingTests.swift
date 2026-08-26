import Foundation
import Testing
@testable import Talaria

/// Lane M PR 2 (OPEN_ITEMS #114): multi-profile routing — session-host
/// affinity, list merging, pinned sensors, push-watch routing, and the
/// dormant-token freshness policy.
@Suite(.serialized)
struct BackendProfileRoutingTests {

    // MARK: - Fixtures

    private final class RoutingStubURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private final class RequestLog: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [(host: String, path: String, authorization: String?)] = []

        func record(_ request: URLRequest) {
            lock.lock()
            defer { lock.unlock() }
            entries.append((
                host: request.url?.host ?? "",
                path: request.url?.path ?? "",
                authorization: request.value(forHTTPHeaderField: "Authorization")
            ))
        }

        var all: [(host: String, path: String, authorization: String?)] {
            lock.lock()
            defer { lock.unlock() }
            return entries
        }
    }

    @MainActor
    private func makePersistence(_ label: String) -> UserDefaultsAppPersistenceStore {
        let suiteName = "profile-routing-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    private static let ojamdSeeds = BackendProfilesStore.MigrationSeeds(
        gatewayBaseURL: "http://ojamd:8642",
        shimBaseURL: "http://ojamd:8765"
    )

    private static func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RoutingStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func jsonResponse(for request: URLRequest, body: String) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }

    @MainActor
    private func makeClient(
        persistence: UserDefaultsAppPersistenceStore,
        active: BackendProfile,
        others: [BackendProfile],
        keys: [UUID: String],
        activeKey: String,
        index: SessionProfileIndexStore
    ) -> SessionsHermesClient {
        let all = [active] + others
        return SessionsHermesClient(
            baseURLProvider: { active.gatewayBaseURL },
            apiKeyProvider: { activeKey },
            journal: ConversationJournalStore(persistence: persistence),
            transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
            session: Self.stubbedSession(),
            activeProfileIDProvider: { active.id },
            profileIndex: index,
            profileEndpointResolver: { profileID in
                guard let profile = all.first(where: { $0.id == profileID }),
                      let key = keys[profileID] else { return nil }
                return (profile.gatewayBaseURL, key)
            },
            chatProfilesProvider: { all }
        )
    }

    // MARK: - M-5: session-host affinity

    @Test @MainActor
    func openSessionRoutesToBirthProfileGatewayAfterSwitch() async throws {
        // Active profile is OJAMD, but the session was born on the Mac —
        // opening it must hit the MAC's gateway with the MAC's key.
        let persistence = makePersistence("affinity")
        let ojamd = BackendProfile(name: "OJAMD", gatewayBaseURL: "http://ojamd:8642", usesLegacyCredentialKeys: true)
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "http://macmini:8642")

        let index = SessionProfileIndexStore(persistence: persistence)
        index.record(sessionID: "api_mac", profileID: mac.id)

        let client = makeClient(
            persistence: persistence,
            active: ojamd,
            others: [mac],
            keys: [mac.id: "key-mac"],
            activeKey: "key-ojamd",
            index: index
        )

        let log = RequestLog()
        RoutingStubURLProtocol.requestHandler = { request in
            log.record(request)
            return Self.jsonResponse(for: request, body: #"{"session_id": "api_mac", "data": []}"#)
        }
        defer { RoutingStubURLProtocol.requestHandler = nil }

        _ = try await client.openSession("api_mac")

        let requests = log.all
        #expect(requests.count == 1)
        #expect(requests.first?.host == "macmini")
        #expect(requests.first?.authorization == "Bearer key-mac")
    }

    @Test @MainActor
    func newSessionOverrideBirthsHopOnNamedProfileWithoutFlippingActive() async throws {
        // M-16's mechanism: pendingNewSessionProfileID targets ONE fresh hop
        // at a non-active profile; the active profile is untouched and the
        // override is consumed.
        let persistence = makePersistence("override")
        let ojamd = BackendProfile(name: "OJAMD", gatewayBaseURL: "http://ojamd:8642", usesLegacyCredentialKeys: true)
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "http://macmini:8642")

        let index = SessionProfileIndexStore(persistence: persistence)
        let client = makeClient(
            persistence: persistence,
            active: ojamd,
            others: [mac],
            keys: [mac.id: "key-mac"],
            activeKey: "key-ojamd",
            index: index
        )

        let log = RequestLog()
        RoutingStubURLProtocol.requestHandler = { request in
            log.record(request)
            let path = request.url?.path ?? ""
            if path == "/api/sessions" {
                return Self.jsonResponse(for: request, body: #"{"session": {"id": "api_new"}}"#)
            }
            // #382: the turn rides the runs plane.
            if path.hasSuffix("/messages") {
                return Self.jsonResponse(for: request, body: #"{"session_id": "api_new", "data": []}"#)
            }
            if path == "/v1/runs" {
                return Self.jsonResponse(for: request, body: #"{"run_id": "run_route_1", "status": "started"}"#)
            }
            if path == "/v1/runs/run_route_1" {
                return Self.jsonResponse(for: request, body: #"{"run_id": "run_route_1", "status": "completed", "output": "ok"}"#)
            }
            return Self.jsonResponse(for: request, body: #"{"message": {"content": "ok"}}"#)
        }
        defer { RoutingStubURLProtocol.requestHandler = nil }

        client.pendingNewSessionProfileID = mac.id
        let reply = await client.send(message: "hello mac", attachments: [], clientMessageID: UUID())

        #expect(reply.status == .delivered)
        let requests = log.all
        // #241: creates are preceded by one catalog probe. #382: the runs
        // turn's family is catalog + create + history + submit + one status
        // poll — and the allSatisfy rows below are the proof that EVERY one
        // of them honours the override profile (host + key), which is the
        // M-16 property this test exists to pin.
        #expect(requests.count == 5)
        #expect(requests.allSatisfy { $0.host == "macmini" })
        #expect(requests.allSatisfy { $0.authorization == "Bearer key-mac" })
        #expect(client.pendingNewSessionProfileID == nil)
        // The hop and the index both carry the Mac as the birth host.
        let journal = persistence.loadConversationJournal()
        #expect(journal?.activeHop?.profileID == mac.id)
        #expect(index.profileID(forSessionID: "api_new") == mac.id)
    }

    // MARK: - M-5: list merging

    @Test @MainActor
    func mergeSessionListsInterleavesByRecencyAndPassesSingleListThrough() {
        func info(_ id: String, minutesAgo: Int?, profile: String) -> HermesSessionInfo {
            HermesSessionInfo(
                id: id, title: nil, preview: nil, model: nil, source: nil,
                messageCount: 1,
                lastActive: minutesAgo.map { Date(timeIntervalSinceNow: -Double($0) * 60) },
                isActive: false,
                profileID: UUID(),
                profileName: profile
            )
        }

        let ojamdRows = [info("o1", minutesAgo: 5, profile: "OJAMD"), info("o2", minutesAgo: 120, profile: "OJAMD")]
        let macRows = [info("m1", minutesAgo: 1, profile: "Mac"), info("m2", minutesAgo: 60, profile: "Mac"), info("m3", minutesAgo: nil, profile: "Mac")]

        let merged = SessionsHermesClient.mergeSessionLists([ojamdRows, macRows])
        #expect(merged.map(\.id) == ["m1", "o1", "m2", "o2", "m3"])

        // Single list: byte-identical passthrough (pre-Lane-M order).
        let single = SessionsHermesClient.mergeSessionLists([macRows])
        #expect(single.map(\.id) == ["m1", "m2", "m3"])
    }

    // MARK: - M-7: push-watch routing

    @Test @MainActor
    func pushWatchRoutingPrefersBirthProfileAndFallsBackToActive() {
        var index = SessionProfileIndex()
        let ojamd = UUID()
        let mac = UUID()
        index.record(sessionID: "api_mac", profileID: mac)

        // Recorded session → its birth profile, regardless of active.
        #expect(index.routingProfileID(forSessionID: "api_mac", activeProfileID: ojamd) == mac)
        // Unrecorded (pre-Lane-M) session → the active/migrated profile.
        #expect(index.routingProfileID(forSessionID: "api_legacy", activeProfileID: ojamd) == ojamd)
    }

    // ── M-9: dormant token freshness — TOMBSTONED 2026-08-25 (#309 Lane A)
    //
    // `dormantRefreshPolicyFiresOncePerWindowAndSkipsFreshActiveUnpaired`
    // pinned `DormantTokenRefreshPolicy.profilesDue`: which dormant profiles
    // were due an `auth/refresh`, and the no-thrash floor that kept a failing
    // relay from being re-tried on every foreground.
    //
    // The policy and its caller (`AppContainer
    // .refreshDormantProfileTokensIfNeeded`, and
    // `ProfileRelaySessionFactory.refreshAccessToken` beneath it) are deleted
    // with the relay bootstrap chain: there is no 30-day relay refresh TTL
    // left to strand, on any host. Deleted rather than repointed — its whole
    // subject matter is gone, and the #310 fixture case it carried (a
    // relay-LESS paired profile must not be due) is now true by construction
    // because nothing is ever due.

}

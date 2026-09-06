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

    // MARK: - #430: dropped-run recovery asks the RUN'S host, not the active one

    /// **430-B, the defect's own shape.** A run is submitted under the Mac
    /// profile; the user switches the active profile to OJAMD; the process
    /// dies; the next cold launch reads the pending record and asks the host
    /// for that run's verdict. Before this lane the read went to
    /// `readRunStatus(runID:profileID: nil)`, and nil resolves to the ACTIVE
    /// profile — so the question reached OJAMD, which has never heard of the
    /// run, answered 404, and the 404 was classified `.gone`: a real answer
    /// destroyed as "the host forgot it".
    ///
    /// Isolating mutation: restore `profileID: nil` inside `resolveDroppedRun`
    /// → this row reds (host `ojamd`, `Bearer key-ojamd`) and the two rows
    /// below stay green, because their fallbacks resolve to the same nil.
    @Test @MainActor
    func droppedRunRecoveryReadsTheRecordsProfileNotTheActiveOne() async throws {
        let persistence = makePersistence("recovery-record-profile")
        let ojamd = BackendProfile(name: "OJAMD", gatewayBaseURL: "http://ojamd:8642", usesLegacyCredentialKeys: true)
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "http://macmini:8642")

        // Deliberately EMPTY: the record's own profile must be enough. If the
        // read only works because the birth index happens to agree, this row
        // is not measuring what it claims.
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
            return Self.jsonResponse(
                for: request,
                body: #"{"run_id": "run_dropped_1", "status": "completed", "output": "the answer that survived"}"#
            )
        }
        defer { RoutingStubURLProtocol.requestHandler = nil }

        let resolution = await client.resolveDroppedRun(
            runID: "run_dropped_1",
            sessionID: "api_mac_dropped",
            profileID: mac.id
        )

        guard case .answered(let content, _) = resolution else {
            Issue.record("expected the run's host to answer, got \(String(describing: resolution))")
            return
        }
        #expect(content == "the answer that survived")

        let requests = log.all
        #expect(requests.count == 1)
        #expect(requests.first?.path == "/v1/runs/run_dropped_1")
        #expect(requests.first?.host == "macmini", "the recovery read must address the run's OWN host")
        #expect(requests.first?.authorization == "Bearer key-mac", "and carry that host's key")
    }

    /// **430-B, the legacy record.** A record written before this lane carries
    /// no profile at all (it decodes `nil`). The session's BIRTH profile is
    /// the next-best answer and is the same resolution `openSession` already
    /// uses (`SessionsHermesClient.swift` — `profileIndex?.profileID(forSessionID:)`).
    ///
    /// Isolating mutation: drop the `profileIndex` term from the recovery
    /// resolution → this row reds (host `ojamd`) while the row above stays
    /// green.
    @Test @MainActor
    func aLegacyRecordWithNoProfileFallsBackToTheSessionsBirthHost() async throws {
        let persistence = makePersistence("recovery-birth-profile")
        let ojamd = BackendProfile(name: "OJAMD", gatewayBaseURL: "http://ojamd:8642", usesLegacyCredentialKeys: true)
        let mac = BackendProfile(name: "Mac Mini", gatewayBaseURL: "http://macmini:8642")

        let index = SessionProfileIndexStore(persistence: persistence)
        index.record(sessionID: "api_mac_legacy", profileID: mac.id)

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
            return Self.jsonResponse(
                for: request,
                body: #"{"run_id": "run_legacy_1", "status": "completed", "output": "legacy answer"}"#
            )
        }
        defer { RoutingStubURLProtocol.requestHandler = nil }

        _ = await client.resolveDroppedRun(
            runID: "run_legacy_1",
            sessionID: "api_mac_legacy",
            profileID: nil
        )

        let requests = log.all
        #expect(requests.count == 1)
        #expect(requests.first?.host == "macmini", "a profile-less record still knows its session's birth host")
        #expect(requests.first?.authorization == "Bearer key-mac")
    }

    /// **430-B, the honest last resort.** Neither the record nor the index
    /// knows the host — a pre-Lane-M session id. Only then does the active
    /// profile answer, which is exactly today's behaviour and must stay
    /// byte-identical for the single-profile user.
    @Test @MainActor
    func withNeitherRecordNorBirthProfileRecoveryAsksTheActiveHost() async throws {
        let persistence = makePersistence("recovery-active-fallback")
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
            return Self.jsonResponse(
                for: request,
                body: #"{"run_id": "run_unknown_1", "status": "completed", "output": "active answer"}"#
            )
        }
        defer { RoutingStubURLProtocol.requestHandler = nil }

        _ = await client.resolveDroppedRun(
            runID: "run_unknown_1",
            sessionID: "api_prelane_m",
            profileID: nil
        )

        let requests = log.all
        #expect(requests.count == 1)
        #expect(requests.first?.host == "ojamd", "unknown on both counts → the active host, as before")
        #expect(requests.first?.authorization == "Bearer key-ojamd")
    }

    /// **430-B's control — the WARM in-turn poll is untouched.** #285's
    /// frozen-endpoint rule owns the poll that runs INSIDE a live turn: it
    /// carries the turn's already-resolved `ResolvedEndpoint`, which wins over
    /// any profile resolution. This lane changed the COLD entry point only, so
    /// this row must stay green with the bytes at `pollRunToTerminal`
    /// unedited — and it is the row that would catch a "fix" that made the
    /// frozen endpoint negotiable.
    @Test @MainActor
    func theWarmInTurnPollStillRidesItsFrozenEndpointAcrossASwitch() async throws {
        let persistence = makePersistence("warm-poll-frozen")
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
            return Self.jsonResponse(
                for: request,
                body: #"{"run_id": "run_warm_1", "status": "completed", "output": "warm answer"}"#
            )
        }
        defer { RoutingStubURLProtocol.requestHandler = nil }

        // The turn's ONE resolution, frozen at birth on the Mac — the active
        // profile is OJAMD throughout.
        let frozen = SessionsHermesClient.ResolvedEndpoint(baseURL: "http://macmini:8642", apiKey: "key-mac")
        let snapshot = await client.pollRunToTerminal(
            runID: "run_warm_1",
            profileID: nil,
            endpoint: frozen
        )

        #expect(snapshot?.status == "completed")
        let requests = log.all
        #expect(requests.count == 1)
        #expect(requests.first?.host == "macmini", "#285: the frozen endpoint wins over the live profile, still")
        #expect(requests.first?.authorization == "Bearer key-mac")
    }

    // MARK: - #430-A: the record carries the host it was SENT under

    /// **430-A.** The field is identity only — a profile UUID, never a key or
    /// a URL (the round-trip below is the pin that keeps it that way: a
    /// `PendingRunRecord` whose JSON grew a secret would fail review here
    /// first). And a record written by ANY build before this lane decodes
    /// with `profileID == nil` rather than failing to decode at all — a
    /// decode failure presents downstream as a silent unpair (#42), so the
    /// legacy arm is the one that must not be assumed.
    ///
    /// Isolating mutation: make `PendingRunRecord.profileID` non-optional
    /// (`UUID`) → the legacy arm reds (`nil` decode) and the round-trip stays
    /// green, which is precisely why both arms are here.
    @Test
    func thePendingRunRecordCarriesItsSendProfileAndLegacyRecordsDecodeNil() throws {
        let sendProfile = UUID()
        let record = PendingRunRecord(
            sessionId: "api_mac_dropped",
            runId: "run_dropped_1",
            userMessageID: UUID(),
            conversationID: UUID(),
            sentAt: Date(timeIntervalSince1970: 1_757_000_000),
            partialReasoning: nil,
            profileID: sendProfile
        )

        let encoded = try JSONEncoder().encode(record)
        let round = try JSONDecoder().decode(PendingRunRecord.self, from: encoded)
        #expect(round == record)
        #expect(round.profileID == sendProfile)

        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(!json.contains("http"), "identity only — no URL may ride the record")
        #expect(!json.contains("Bearer"), "identity only — no key may ride the record")

        // A record written before this lane: the key is simply absent.
        let legacyJSON = #"{"sessionId":"api_mac_dropped","runId":"run_dropped_1","userMessageID":"11111111-1111-1111-1111-111111111111","conversationID":"22222222-2222-2222-2222-222222222222","sentAt":747000000.0}"#
        let legacy = Data(legacyJSON.utf8)
        let decodedLegacy = try JSONDecoder().decode(PendingRunRecord.self, from: legacy)
        #expect(decodedLegacy.profileID == nil, "a legacy record decodes, and knows it does not know its host")
        #expect(decodedLegacy.runId == "run_dropped_1")
    }

}

import CoreLocation
import Foundation
@preconcurrency import MapKit
import os
import UIKit

private let sensorLog = Logger(subsystem: "org.aethyrion.talaria", category: "SensorUpload")

struct SensorOutboxState: Codable, Hashable, Sendable {
    struct PendingLocation: Codable, Hashable, Sendable {
        let latitude: Double
        let longitude: Double
        let altitude: Double?
        let accuracy: Double
        let recordedAt: Date
    }

    struct PendingHealthSample: Codable, Hashable, Sendable {
        let metric: String
        let value: Double
        let unit: String
        let startAt: Date
        let endAt: Date?

        private static let windowedMetrics: Set<String> = [
            "steps",
            "active_calories",
            "distance_walking",
            "workout_minutes",
            "stand_hours",
            "sleep_duration",
        ]

        var dedupeKey: String {
            if Self.windowedMetrics.contains(metric) {
                return "\(metric)|\(unit)|\(startAt.timeIntervalSince1970)"
            }

            return [
                metric,
                unit,
                String(startAt.timeIntervalSince1970),
                String(endAt?.timeIntervalSince1970 ?? 0)
            ].joined(separator: "|")
        }
    }

    var pendingLocation: PendingLocation?
    var pendingHealthSamples: [PendingHealthSample] = []
    /// Health samples dropped to the backlog cap (#104), cumulative until
    /// `resetOutbox()`. Persisted so the loss stays visible across launches
    /// while a capped backlog is still pending. (A fully drained outbox is
    /// cleared from disk, so the tally survives in-memory only after that —
    /// acceptable: the drop matters most while the backlog it bounded exists.)
    var droppedHealthSampleCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case pendingLocation
        case pendingHealthSamples
        case droppedHealthSampleCount
    }

    var isEmpty: Bool {
        pendingLocation == nil && pendingHealthSamples.isEmpty
    }

    mutating func enqueue(location update: LocationUpdate) {
        pendingLocation = PendingLocation(
            latitude: update.latitude,
            longitude: update.longitude,
            altitude: update.altitude,
            accuracy: update.accuracy,
            recordedAt: update.timestamp
        )
    }

    mutating func enqueue(healthSamples: [HealthSnapshot.Sample]) {
        for sample in healthSamples {
            let pending = PendingHealthSample(
                metric: sample.metric,
                value: sample.value,
                unit: sample.unit,
                startAt: sample.startAt,
                endAt: sample.endAt
            )
            if let index = pendingHealthSamples.firstIndex(where: { $0.dedupeKey == pending.dedupeKey }) {
                pendingHealthSamples[index] = pending
            } else {
                pendingHealthSamples.append(pending)
            }
        }
    }

    /// Bounds the health backlog to `cap` by dropping the OLDEST samples
    /// (#104). The drain sends front-first, so the front of the array is the
    /// stalest data — the least valuable to a live agent once a connector
    /// outage has let the backlog grow. `protectingPrefix` shields the first
    /// N samples from the trim: while a drain has the front chunk in flight,
    /// eating into it would make the post-delivery removal delete samples
    /// that were never uploaded. Returns how many were dropped; the tally
    /// also lands in `droppedHealthSampleCount` for the diagnostics surface.
    @discardableResult
    mutating func enforceHealthBacklogCap(_ cap: Int, protectingPrefix protected: Int = 0) -> Int {
        let overflow = pendingHealthSamples.count - cap
        guard overflow > 0 else { return 0 }
        let start = min(protected, pendingHealthSamples.count - overflow)
        pendingHealthSamples.removeSubrange(start..<(start + overflow))
        droppedHealthSampleCount += overflow
        return overflow
    }
}

// Pre-#104 caches lack `droppedHealthSampleCount` — decode additively so an
// existing persisted outbox never reads as missing state (the #42 lesson;
// same shape as the ConversationJournal fields and the #59 voice-memo
// precedent). Encoding stays synthesized. This init lives in an extension so
// the struct keeps its memberwise and default initializers.
extension SensorOutboxState {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pendingLocation = try container.decodeIfPresent(PendingLocation.self, forKey: .pendingLocation)
        pendingHealthSamples = try container.decodeIfPresent([PendingHealthSample].self, forKey: .pendingHealthSamples) ?? []
        droppedHealthSampleCount = try container.decodeIfPresent(Int.self, forKey: .droppedHealthSampleCount) ?? 0
    }
}

/// Coordinates durable sensor uploads from the phone to the relay.
///
/// The relay only ACKs a sample once the connector has received and stored it,
/// so sensor state is persisted locally until a real delivery succeeds.
@MainActor
@Observable
final class SensorUploadService {
    private struct SensorLocationBody: Encodable {
        let latitude: Double
        let longitude: Double
        let altitude: Double?
        let accuracy: Double
        let address: String?
        let recordedAt: String
    }

    private struct SensorHealthBody: Encodable {
        struct Sample: Encodable {
            let metric: String
            let value: Double
            let unit: String
            let startAt: String
            let endAt: String?
        }

        let samples: [Sample]
    }

    private struct DeliveryResult: Decodable {
        let deliveryState: String

        var wasDelivered: Bool {
            deliveryState == "delivered"
        }
    }

    private enum HealthUploadOutcome {
        case delivered
        /// Relay accepted the payload but the connector was busy (202 "retry")
        /// — the same chunk should be re-sent after a backoff.
        case retry
        /// Permanent payload rejection (relay 400/422): identical bytes can
        /// never deliver — the chunk carries at least one poison sample that
        /// must be isolated, not retried forever (#24a follow-up).
        case rejected(String)
        /// Transient failure (network / 5xx / failed token refresh) — the same
        /// payload may succeed later; keep the backlog.
        case failed
    }

    private enum LocationUploadOutcome {
        case delivered
        /// Relay accepted the payload but the connector was busy (202 "retry")
        /// — the same fix should be re-sent after a backoff.
        case retry
        /// Permanent payload rejection — this exact fix can never deliver.
        case rejected
        case failed
    }

    /// What a single authorized POST attempt resolved to, separating the
    /// can-never-succeed rejections from retry-worthy failures. Previously
    /// every non-401 failure collapsed into one undifferentiated nil, so a
    /// single 422 sample wedged the entire health outbox forever (#24a).
    private enum UploadAttempt {
        case response(DeliveryResult?)
        case rejected(String)
        case transientFailure
    }

    /// The relay hard-caps SensorHealthRequest.samples at 100
    /// (relay/app/schemas.py) — larger payloads 422 before any field check,
    /// so backlog drains must be chunked (#24a).
    private static let healthUploadChunkSize = 100
    /// How many consecutive connector-busy (202 "retry") responses to absorb
    /// per drain before giving up and leaving the rest for the next trigger.
    static let maxHealthBusyRetries = 3
    /// How many consecutive connector-busy (202 "retry") responses to absorb
    /// for location uploads before falling through to health.
    private static let maxLocationBusyRetries = 2

    /// #104: how long enqueue-driven outbox writes may coalesce before one
    /// trailing write lands. A crash inside this window loses at most this
    /// many seconds of sensor samples (plus the store's brief off-main write
    /// handoff) — explicitly accepted in the item.
    static let persistDebounceInterval: TimeInterval = 5
    /// #104: hard bound on `pendingHealthSamples`. 500 = five full relay
    /// chunks (`healthUploadChunkSize`), an order of magnitude above routine
    /// backlogs but 4× below the ~2k the #103 outage accumulated — bounding
    /// the whole-outbox encode cost that outage turned into a thermal loop.
    /// Windowed metrics dedupe to ~one entry per window, so real loss only
    /// starts under a sustained multi-day outage of instantaneous samples.
    static let maxPendingHealthSamples = 500

    private let apiClient: RelayAPIClient
    private let accessTokenProvider: @MainActor () async -> String?
    private let accessTokenRefresher: @MainActor () async -> String?
    private let persistence: AppPersistenceStoreProtocol
    private let isPairedProvider: @MainActor () -> Bool
    /// #137 master opt-in: when false, start() is a no-op — the capture/drain
    /// loop never activates. Sits ON TOP of the Hermes gating (isPaired), not
    /// instead of it. Must be a fast local read (#136 splash path).
    private let isSensorStreamingEnabled: @MainActor () -> Bool
    // In-app revoke gates (#6): when false, start() must not wire or (re)start
    // that sensor — otherwise the launch-time health re-assert / location
    // startMonitoring resurrects a collection the user revoked.
    private let isHealthCollectionEnabled: @MainActor () -> Bool
    private let isLocationCollectionEnabled: @MainActor () -> Bool
    /// #137: motion joins the per-sensor gates (it never had a #6 one).
    private let isMotionCollectionEnabled: @MainActor () -> Bool
    private let locationService: LiveLocationService
    private let healthService: LiveHealthService
    private let motionService: LiveMotionService?

    private let notificationCenter: NotificationCenter
    /// Awaits one debounce window. Injected so tests can gate the interval
    /// deterministically instead of sleeping (#104).
    private let persistDebounceWait: @MainActor () async -> Void
    /// Awaits one connector-busy backoff step (the 2/4/8s ladder in the
    /// drain phases). Injected so retry-exhaustion tests run
    /// deterministically instead of sleeping through the whole ladder.
    private let busyBackoffWait: @MainActor (TimeInterval) async -> Void

    private var isActive = false
    private var isDraining = false
    private var outboxState: SensorOutboxState
    /// The single trailing debounced write, if one is armed. Its presence IS
    /// the dirty flag: every outbox mutation either arms it or persists
    /// immediately. Internal read-only so tests can await the trailing edge;
    /// @ObservationIgnored keeps per-tick mutations out of the observation
    /// registrar (no view reads it).
    @ObservationIgnored private(set) var pendingOutboxPersistTask: Task<Void, Never>?
    /// Set when the CURRENT drain removed delivered/consumed work from the
    /// outbox — those removals must flush at drain end (a re-send after a
    /// crash is worse than a re-tick). Enqueue dirt from concurrent sensor
    /// ticks rides the normal debounce instead: an unconditional drain-end
    /// flush would re-create the per-tick write cadence in the
    /// paired-but-failing case #104 exists to kill.
    @ObservationIgnored private var drainMutatedOutbox = false
    /// Size of the health chunk currently awaiting an upload response; the
    /// backlog cap must never trim inside this prefix.
    @ObservationIgnored private var inFlightHealthChunkCount = 0

    /// Most recent drain attempt outcome (for the #15 sensor diagnostics panel).
    private(set) var lastDrainSummary: String?
    private(set) var lastDrainAt: Date?

    /// #113: repeated retry-exhaustion is the dead-connector shape — decide
    /// once per drain cycle whether it warrants the inbox alert. Pure state,
    /// fed at drain end; no view reads it.
    @ObservationIgnored private var outageAlertPolicy = ConnectorOutageAlertPolicy()
    /// Wired by AppContainer to the inbox: `true` raises the deduped
    /// connector-down alert, `false` clears it after a delivery proves the
    /// connector alive.
    @ObservationIgnored var onConnectorOutageAlert: (@MainActor (_ raised: Bool) -> Void)?

    private let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(
        apiClient: RelayAPIClient,
        accessTokenProvider: @escaping @MainActor () async -> String?,
        accessTokenRefresher: @escaping @MainActor () async -> String? = { nil },
        persistence: AppPersistenceStoreProtocol,
        isPairedProvider: @escaping @MainActor () -> Bool,
        isSensorStreamingEnabled: @escaping @MainActor () -> Bool = { true },
        isHealthCollectionEnabled: @escaping @MainActor () -> Bool = { true },
        isLocationCollectionEnabled: @escaping @MainActor () -> Bool = { true },
        isMotionCollectionEnabled: @escaping @MainActor () -> Bool = { true },
        locationService: LiveLocationService,
        healthService: LiveHealthService,
        motionService: LiveMotionService? = nil,
        notificationCenter: NotificationCenter = .default,
        persistDebounceWait: (@MainActor () async -> Void)? = nil,
        busyBackoffWait: (@MainActor (TimeInterval) async -> Void)? = nil
    ) {
        self.apiClient = apiClient
        self.accessTokenProvider = accessTokenProvider
        self.accessTokenRefresher = accessTokenRefresher
        self.persistence = persistence
        self.isPairedProvider = isPairedProvider
        self.isSensorStreamingEnabled = isSensorStreamingEnabled
        self.isHealthCollectionEnabled = isHealthCollectionEnabled
        self.isLocationCollectionEnabled = isLocationCollectionEnabled
        self.isMotionCollectionEnabled = isMotionCollectionEnabled
        self.locationService = locationService
        self.healthService = healthService
        self.motionService = motionService
        self.notificationCenter = notificationCenter
        self.persistDebounceWait = persistDebounceWait ?? {
            try? await Task.sleep(for: .seconds(SensorUploadService.persistDebounceInterval))
        }
        self.busyBackoffWait = busyBackoffWait ?? { seconds in
            try? await Task.sleep(for: .seconds(seconds))
        }
        self.outboxState = persistence.loadSensorOutboxState()
        registerLifecycleFlushObservers()
    }

    // MARK: - Diagnostics surface (#15)

    /// Read-only snapshot of the sensor pipeline's internal state for the in-app
    /// diagnostics panel. Computed from observable state, so a SwiftUI view that
    /// reads it updates as the pipeline changes.
    struct SensorDiagnostics {
        let isActive: Bool
        let isPaired: Bool
        let pendingLocation: PendingLocationInfo?
        let pendingHealthCount: Int
        /// #104: health samples dropped to the backlog cap since the outbox
        /// was last reset — non-zero means a connector outage outlasted the
        /// cap and the oldest samples were sacrificed.
        let droppedHealthCount: Int
        let lastDrainSummary: String?
        let lastDrainAt: Date?
        let locationAuthorization: LocationAuthorizationLevel
        let locationAccuracyLabel: String
        let healthAuthorization: PermissionStatus
        let motionAuthorization: PermissionStatus

        struct PendingLocationInfo {
            let latitude: Double
            let longitude: Double
            let recordedAt: Date
        }
    }

    var sensorDiagnostics: SensorDiagnostics {
        SensorDiagnostics(
            isActive: isActive,
            isPaired: isPairedProvider(),
            pendingLocation: outboxState.pendingLocation.map {
                .init(latitude: $0.latitude, longitude: $0.longitude, recordedAt: $0.recordedAt)
            },
            pendingHealthCount: outboxState.pendingHealthSamples.count,
            droppedHealthCount: outboxState.droppedHealthSampleCount,
            lastDrainSummary: lastDrainSummary,
            lastDrainAt: lastDrainAt,
            locationAuthorization: locationService.authorizationLevel,
            locationAccuracyLabel: locationService.accuracyLevel.displayLabel,
            healthAuthorization: healthService.authorizationStatus,
            motionAuthorization: motionService?.authorizationStatus ?? .unsupported
        )
    }

    /// Whether a non-empty access token is currently retrievable (async).
    func hasValidAccessToken() async -> Bool {
        let token = await accessTokenProvider()
        return token?.isEmpty == false
    }

    private func recordDrain(_ summary: String) {
        lastDrainSummary = summary
        lastDrainAt = Date()
    }

    func start() {
        guard isSensorStreamingEnabled() else {
            sensorLog.notice("start() skipped — sensor streaming not opted in (#137)")
            return
        }
        guard !isActive else {
            sensorLog.notice("start() skipped — already active")
            return
        }
        isActive = true
        outboxState = persistence.loadSensorOutboxState()
        // #104: a pre-cap cache can carry an oversized backlog (the #103
        // outage hit ~2k samples) — bound it up front so every subsequent
        // encode is capped, not just post-enqueue ones. The dropped samples
        // are the stalest end of an already multi-day-old backlog.
        let dropped = outboxState.enforceHealthBacklogCap(Self.maxPendingHealthSamples)
        if dropped > 0 {
            scheduleOutboxPersist()
            sensorLog.warning("start() — loaded backlog exceeded cap: dropped \(dropped) oldest health sample(s)")
        }
        sensorLog.notice("start() — activating sensor pipeline. Outbox: loc=\(self.outboxState.pendingLocation != nil), health=\(self.outboxState.pendingHealthSamples.count)")

        if isLocationCollectionEnabled() {
            locationService.onLocationUpdate = { [weak self] update in
                guard let self else { return }
                Task { @MainActor in
                    sensorLog.notice("📍 location update: (\(update.latitude), \(update.longitude)) accuracy=\(update.accuracy)")
                    self.recordLocationUpdate(update)
                    await self.drainOutboxIfPossible()
                }
            }
        } else {
            sensorLog.notice("start() — location collection disabled in-app (#6); not wiring")
        }

        if isHealthCollectionEnabled() {
            healthService.onHealthUpdate = { [weak self] changedIdentifiers in
                guard let self else { return }
                Task { @MainActor in
                    sensorLog.notice("💓 health update for: \(changedIdentifiers.joined(separator: ", "), privacy: .public)")
                    await self.captureHealthSnapshot(changedIdentifiers: changedIdentifiers)
                }
            }
        } else {
            sensorLog.notice("start() — health collection disabled in-app (#6); not wiring")
        }

        if isMotionCollectionEnabled() {
            motionService?.onActivityUpdate = { [weak self] activityCode in
                guard let self else { return }
                Task { @MainActor in
                    sensorLog.notice("🏃 activity update: code=\(activityCode.rawValue)")
                    let now = Date()
                    let sample = HealthSnapshot.Sample(
                        metric: "user_activity",
                        value: Double(activityCode.rawValue),
                        unit: "activity_code",
                        startAt: now,
                        endAt: nil
                    )
                    self.recordHealthSamples([sample])
                    await self.drainOutboxIfPossible()
                }
            }
        } else {
            sensorLog.notice("start() — motion collection disabled in-app (#137); not wiring")
        }

        if isLocationCollectionEnabled() {
            locationService.startMonitoring()
        }
        if isMotionCollectionEnabled() {
            motionService?.startMonitoring()
        }

        // Health authorization is in-memory only: LiveHealthService resets it to
        // .notDetermined on every launch, and Apple's read-privacy model means it
        // cannot be recovered via authorizationStatus(for:) (read status stays hidden).
        // collectSnapshot() hard-gates on .authorized, so without re-asserting here,
        // every snapshot returns nil after a relaunch even when the user already
        // granted access. Re-request on each start() to restore .authorized AND
        // re-enable background delivery. For read-only types iOS shows the system
        // sheet at most once per install, so repeat calls after the first decision
        // are silent — no nagging, even on denial.
        if isHealthCollectionEnabled() {
            Task { [weak self] in
                guard let self else { return }
                let status = await self.healthService.requestAuthorization()
                self.healthService.startMonitoring()
                sensorLog.notice("start() — health auth re-asserted: \(String(describing: status), privacy: .public)")
                await self.captureHealthSnapshot(forceFullRefresh: true)
            }
        }

        sensorLog.notice("start() — monitoring started (loc/motion; health pending re-auth). loc auth=\(String(describing: self.locationService.authorizationStatus), privacy: .public)")
    }

    func stop() {
        isActive = false
        isDraining = false
        locationService.onLocationUpdate = nil
        healthService.onHealthUpdate = nil
        motionService?.onActivityUpdate = nil
        locationService.stopMonitoring()
        healthService.stopMonitoring()
        motionService?.stopMonitoring()
        // #104: teardown must not strand a debounced write — the callbacks
        // are gone, so nothing else will ever flush it.
        flushOutboxPersistence()
    }

    func resetOutbox() {
        // A trailing debounced write would resurrect the state being reset.
        pendingOutboxPersistTask?.cancel()
        pendingOutboxPersistTask = nil
        outboxState = SensorOutboxState()
        persistence.clearSensorOutboxState()
    }

    // MARK: - Outbox intake (#104)

    /// Enqueue + debounced persist for a location fix. The write cadence is
    /// the only change from the pre-#104 inline path — collection and drain
    /// semantics are untouched.
    func recordLocationUpdate(_ update: LocationUpdate) {
        outboxState.enqueue(location: update)
        scheduleOutboxPersist()
    }

    /// Enqueue + cap + debounced persist for health samples. Health
    /// snapshots and motion-activity ticks share this path, so the cap
    /// bounds both streams. An in-flight drain chunk is shielded from the
    /// trim — see `enforceHealthBacklogCap`.
    func recordHealthSamples(_ samples: [HealthSnapshot.Sample]) {
        outboxState.enqueue(healthSamples: samples)
        let dropped = outboxState.enforceHealthBacklogCap(
            Self.maxPendingHealthSamples,
            protectingPrefix: inFlightHealthChunkCount
        )
        if dropped > 0 {
            let total = outboxState.droppedHealthSampleCount
            // At-cap steady state drops on every tick for the whole outage —
            // log the first drop and each 100-sample milestone, not each tick.
            if total == dropped || total / 100 != (total - dropped) / 100 {
                sensorLog.warning("health backlog at cap (\(Self.maxPendingHealthSamples)) — dropped \(dropped) oldest sample(s); \(total) dropped since last reset")
            }
        }
        scheduleOutboxPersist()
    }

    // MARK: - In-app revoke (#6 / OPEN_ITEMS #23)

    /// Halts HealthKit use now: observers stopped, background delivery
    /// disabled, queued samples dropped. The caller persists the
    /// `healthCollectionEnabled` flag that keeps start() from re-asserting.
    func disableHealthCollection() async {
        healthService.onHealthUpdate = nil
        healthService.stopMonitoring()
        await healthService.disableBackgroundDelivery()
        outboxState.pendingHealthSamples.removeAll()
        persistOutboxImmediately()
        sensorLog.notice("health collection revoked in-app — observers stopped, background delivery off, outbox cleared")
    }

    /// Halts location use now: monitoring sessions invalidated, queued fix
    /// dropped. The caller persists the `locationCollectionEnabled` flag.
    func disableLocationCollection() {
        locationService.onLocationUpdate = nil
        locationService.stopMonitoring()
        outboxState.pendingLocation = nil
        persistOutboxImmediately()
        sensorLog.notice("location collection revoked in-app — monitoring stopped, pending fix dropped")
    }

    /// Halts motion use now (#137): activity updates unwired, monitoring
    /// stopped, queued activity samples dropped. The caller persists the
    /// `motionCollectionEnabled` flag that keeps start() from re-wiring.
    func disableMotionCollection() {
        motionService?.onActivityUpdate = nil
        motionService?.stopMonitoring()
        outboxState.pendingHealthSamples.removeAll { $0.metric == "user_activity" }
        persistOutboxImmediately()
        sensorLog.notice("motion collection revoked in-app — monitoring stopped, queued activity samples dropped")
    }

    func handleAppDidBecomeActive() async {
        guard isActive else {
            sensorLog.warning("handleAppDidBecomeActive: service not active — skipping")
            return
        }
        sensorLog.notice("handleAppDidBecomeActive: requesting location + full health refresh")

        if isLocationCollectionEnabled() {
            locationService.requestSingleLocation()
        }
        await captureHealthSnapshot(forceFullRefresh: true)
        await drainOutboxIfPossible()
    }

    func handleSystemLaunch() async {
        guard isActive else {
            sensorLog.warning("handleSystemLaunch: service not active — skipping")
            return
        }
        sensorLog.notice("handleSystemLaunch: capturing health + draining outbox")

        await captureHealthSnapshot()
        await drainOutboxIfPossible()
    }

    private func captureHealthSnapshot(
        forceFullRefresh: Bool = false,
        changedIdentifiers: Set<String>? = nil
    ) async {
        guard isHealthCollectionEnabled() else { return }
        guard
            let snapshot = await healthService.collectSnapshot(
                forceFullRefresh: forceFullRefresh,
                changedIdentifiers: changedIdentifiers
            )
        else {
            sensorLog.notice("captureHealth: collectSnapshot returned nil (auth=\(String(describing: self.healthService.authorizationStatus), privacy: .public))")
            return
        }
        guard !snapshot.samples.isEmpty else {
            sensorLog.notice("captureHealth: snapshot empty (no changed metrics)")
            return
        }
        sensorLog.notice("captureHealth: got \(snapshot.samples.count) samples — \(snapshot.samples.map(\.metric).joined(separator: ", "))")
        recordHealthSamples(snapshot.samples)
        SharedWidgetDataStore.updateHealthMetrics(from: snapshot.samples)
        await drainOutboxIfPossible()
    }

    private func drainOutboxIfPossible() async {
        guard !isDraining else {
            sensorLog.verbose("drain: skipped — already draining")
            return
        }
        guard isActive else {
            sensorLog.warning("drain: BLOCKED — service not active (start() never called or stop()'d)")
            recordDrain("Blocked: pipeline inactive")
            return
        }
        guard isPairedProvider() else {
            sensorLog.warning("drain: BLOCKED — isPairedProvider() returned false")
            recordDrain("Blocked: not paired")
            return
        }

        guard let accessToken = await accessTokenProvider(), !accessToken.isEmpty else {
            sensorLog.warning("drain: BLOCKED — accessTokenProvider() returned nil/empty")
            recordDrain("Blocked: no access token")
            return
        }
        _ = accessToken

        sensorLog.notice("drain: starting. Outbox: loc=\(self.outboxState.pendingLocation != nil), health=\(self.outboxState.pendingHealthSamples.count)")

        isDraining = true
        drainMutatedOutbox = false
        defer { isDraining = false }

        var healthBusyRetries = 0
        var locationBusyRetries = 0

        // #113: what this drain cycle proved about the connector — fed to
        // the outage-alert policy at drain end. A cycle that never attempted
        // an upload (empty outbox) proves nothing and is not an event.
        var cycleAttemptedUpload = false
        var cycleSawDelivery = false
        var cycleSawRetryExhaustion = false

        // ── Location phase ──────────────────────────────────────────
        // Drained independently of health — a location failure (transient
        // or retry-exhausted) falls through to health instead of wedging
        // the entire outbox drain (#27).
        while isActive && isPairedProvider(), let pendingLocation = outboxState.pendingLocation {
            cycleAttemptedUpload = true
            let outcome = await uploadLocation(pendingLocation)
            sensorLog.notice("drain: location upload → \(String(describing: outcome), privacy: .public)")
            switch outcome {
            case .delivered:
                locationBusyRetries = 0
                cycleSawDelivery = true
                clearPendingLocationIfUnchanged(pendingLocation)
            case .rejected:
                locationBusyRetries = 0
                // Permanent rejection: identical bytes can never deliver,
                // and a fresh fix supersedes this one — drop, don't wedge
                // the drain (health waits behind location).
                sensorLog.error("drain: location fix permanently rejected — dropped")
                clearPendingLocationIfUnchanged(pendingLocation)
            case .retry:
                guard locationBusyRetries < Self.maxLocationBusyRetries else {
                    sensorLog.notice("drain: location retries exhausted — deferring to next trigger")
                    recordDrain("Location upload busy — retries exhausted")
                    cycleSawRetryExhaustion = true
                    break
                }
                locationBusyRetries += 1
                let delay = Double(1 << locationBusyRetries)
                sensorLog.notice("drain: location connector busy — retrying in \(delay, privacy: .public)s (attempt \(locationBusyRetries)/\(Self.maxLocationBusyRetries))")
                await busyBackoffWait(delay)
                continue
            case .failed:
                recordDrain("Location upload failed")
                break
            }
            break  // delivered, rejected, retry-exhausted, or failed — exit location phase
        }

        // ── Health phase ────────────────────────────────────────────
        // Independent of location — runs even when location failed above
        // (#27: location failure no longer starves health). Give-up
        // outcomes fall out of the switch to the trailing loop-break: a
        // bare `break` in a case only exits the `switch`, and without the
        // trailing break the loop re-sends the same failing chunk
        // back-to-back with no backoff for as long as the outage lasts
        // (the #113 shape).
        while isActive && isPairedProvider(), !outboxState.pendingHealthSamples.isEmpty {
            // Chunk to the relay's 100-sample cap and send sequentially —
            // the connector handles one payload at a time (#24a).
            let chunk = Array(outboxState.pendingHealthSamples.prefix(Self.healthUploadChunkSize))
            cycleAttemptedUpload = true
            let outcome = await uploadHealthTracked(chunk)
            sensorLog.notice("drain: health chunk (\(chunk.count) of \(self.outboxState.pendingHealthSamples.count) pending) → \(String(describing: outcome), privacy: .public)")
            switch outcome {
            case .delivered:
                healthBusyRetries = 0
                cycleSawDelivery = true
                removeDeliveredHealthPrefix(chunk)
                scheduleOutboxPersist()
                continue
            case .retry:
                // Connector busy — back off, then re-send the same chunk.
                guard healthBusyRetries < Self.maxHealthBusyRetries else {
                    sensorLog.notice("drain: health retries exhausted — deferring to next trigger")
                    recordDrain("Health upload busy — retries exhausted")
                    cycleSawRetryExhaustion = true
                    break
                }
                healthBusyRetries += 1
                let delay = Double(1 << healthBusyRetries)
                sensorLog.notice("drain: connector busy — retrying chunk in \(delay, privacy: .public)s (attempt \(healthBusyRetries)/\(Self.maxHealthBusyRetries))")
                await busyBackoffWait(delay)
                continue
            case .rejected(let message):
                // Permanent 400/422: at least one sample in this chunk can
                // NEVER deliver. Binary-split to deliver the good samples
                // and drop the poison instead of retaining the whole
                // backlog while motion samples pile up behind it (#24a).
                sensorLog.error("drain: health chunk permanently rejected — \(message, privacy: .public); isolating poison sample(s)")
                recordDrain("Isolating rejected health sample(s)")
                guard await resolveRejectedChunk(size: chunk.count) else {
                    sensorLog.notice("drain: poison isolation hit a transient failure — deferring to next trigger")
                    break
                }
                continue
            case .failed:
                recordDrain("Health upload failed")
                break
            }
            break  // retries exhausted, isolation stalled, or failed — exit health phase, keep the backlog
        }
        // #104: chunk-progress writes above are debounced — when this drain
        // consumed work (delivered chunks, cleared fix), force the final
        // state to disk now so it can't be re-sent if the app dies inside
        // the window. A drain that consumed nothing (the outage case: every
        // upload failed) must NOT flush, or the per-tick write cadence #104
        // kills would come straight back via record → failed drain → flush.
        if drainMutatedOutbox {
            drainMutatedOutbox = false
            flushOutboxPersistence()
        }
        sensorLog.notice("drain: finished. Outbox remaining: loc=\(self.outboxState.pendingLocation != nil), health=\(self.outboxState.pendingHealthSamples.count)")
        var drainOutcome = outboxState.isEmpty ? "Delivered · outbox clear" : "Partial · loc=\(outboxState.pendingLocation != nil ? 1 : 0), health=\(outboxState.pendingHealthSamples.count)"
        if outboxState.droppedHealthSampleCount > 0 {
            // Honest loss surfacing (#104): the drain summary is the outbox
            // status line the diagnostics panel already renders.
            drainOutcome += " · \(outboxState.droppedHealthSampleCount) dropped (cap)"
        }
        recordDrain(drainOutcome)

        // #113: one policy event per drain cycle that actually attempted an
        // upload. Any delivery proves the connector alive (clears the alert
        // + streak); a delivery-free cycle that exhausted the busy ladder is
        // the dead-connector shape; anything else breaks the streak.
        if cycleAttemptedUpload {
            let cycleOutcome: ConnectorOutageAlertPolicy.DrainCycleOutcome = cycleSawDelivery
                ? .delivered
                : (cycleSawRetryExhaustion ? .retryExhausted : .inconclusive)
            switch outageAlertPolicy.record(cycleOutcome) {
            case .raiseAlert:
                sensorLog.warning("drain: \(ConnectorOutageAlertPolicy.consecutiveExhaustionThreshold) consecutive retry-exhausted cycles — raising connector-down inbox alert")
                onConnectorOutageAlert?(true)
            case .clearAlert:
                sensorLog.notice("drain: delivery succeeded — clearing connector-down inbox alert")
                onConnectorOutageAlert?(false)
            case .none:
                break
            }
        }
    }

    /// One health upload with its chunk size tracked, so the backlog cap can
    /// shield the in-flight prefix from trimming while the response is
    /// awaited (#104).
    private func uploadHealthTracked(_ samples: [SensorOutboxState.PendingHealthSample]) async -> HealthUploadOutcome {
        inFlightHealthChunkCount = samples.count
        defer { inFlightHealthChunkCount = 0 }
        return await uploadHealth(samples)
    }

    /// Removes a delivered chunk from the front of the health backlog by
    /// dedupe identity, not by count: during the upload's await a revoke
    /// (`disableHealthCollection`) or reset can shrink or replace the array,
    /// and a blind `removeFirst(chunk.count)` would then trap or delete
    /// never-uploaded samples. Positional key comparison is exact — dedupe
    /// keeps keys unique, and the chunk was the array's prefix at send time.
    private func removeDeliveredHealthPrefix(_ chunk: [SensorOutboxState.PendingHealthSample]) {
        var delivered = 0
        while delivered < chunk.count,
              delivered < outboxState.pendingHealthSamples.count,
              outboxState.pendingHealthSamples[delivered].dedupeKey == chunk[delivered].dedupeKey {
            delivered += 1
        }
        outboxState.pendingHealthSamples.removeFirst(delivered)
        drainMutatedOutbox = true
    }

    // MARK: - Outbox persistence (#104)

    /// Debounced persistence: sensor ticks arrive far faster than durability
    /// requires, and each write encodes the WHOLE outbox — pre-#104 that ran
    /// inline on every tick, which #103 measured as a sustained main-actor
    /// encode loop once a connector outage let the backlog grow. Now a tick
    /// marks the outbox dirty and at most one trailing write lands per
    /// debounce window.
    private func scheduleOutboxPersist() {
        guard pendingOutboxPersistTask == nil else { return }
        pendingOutboxPersistTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.persistDebounceWait()
            guard !Task.isCancelled else { return }
            self.pendingOutboxPersistTask = nil
            self.persistOutboxStateNow()
        }
    }

    /// Writes any pending outbox changes NOW. Teardown seams call this so
    /// the debounce window never widens the loss window: `stop()`,
    /// resign-active / background / terminate (via the lifecycle observers),
    /// and drain end. A no-op when no trailing write is armed — an armed
    /// task IS the dirty flag.
    func flushOutboxPersistence() {
        guard let pending = pendingOutboxPersistTask else { return }
        pending.cancel()
        pendingOutboxPersistTask = nil
        persistOutboxStateNow()
    }

    /// Unconditional persist for rare mutations (in-app sensor revokes,
    /// poison-sample resolution) where deferring the write would be
    /// dishonest. Cancels any armed trailing write — this write covers it.
    private func persistOutboxImmediately() {
        pendingOutboxPersistTask?.cancel()
        pendingOutboxPersistTask = nil
        persistOutboxStateNow()
    }

    private func persistOutboxStateNow() {
        if outboxState.isEmpty {
            persistence.clearSensorOutboxState()
        } else {
            persistence.saveSensorOutboxState(outboxState)
        }
    }

    /// #104: the debounce must not survive the app leaving the foreground —
    /// iOS may suspend or kill the process soon after. The flush hands the
    /// state to the store synchronously; the store's actual write lands
    /// off-main moments later, inside the seconds of runway iOS grants after
    /// these notifications. A hard kill with NO notification still loses at
    /// most the debounce window — the loss budget the item accepts.
    /// Observer tokens are intentionally not collected: the service lives
    /// for the process, and tests inject a private center so instances never
    /// cross-talk.
    private func registerLifecycleFlushObservers() {
        let teardownSignals: [Notification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification,
            UIApplication.willTerminateNotification,
        ]
        for name in teardownSignals {
            _ = notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                // UIKit posts these on the main thread and `queue: nil`
                // delivers synchronously there. The Task fallback covers a
                // programmatic off-main post — flush slightly later instead
                // of trapping in assumeIsolated.
                if Thread.isMainThread {
                    MainActor.assumeIsolated { self?.flushOutboxPersistence() }
                } else {
                    Task { @MainActor in self?.flushOutboxPersistence() }
                }
            }
        }
    }

    /// Clears the pending location ONLY when it is still the exact fix that
    /// was just uploaded/resolved. A fresh fix can arrive during the upload's
    /// await and land in `pendingLocation`; blindly nil-ing it afterwards
    /// silently discarded that newer fix (#24a follow-up, item 4). When a
    /// newer fix replaced it, it stays queued and the drain loop sends it next.
    private func clearPendingLocationIfUnchanged(_ uploaded: SensorOutboxState.PendingLocation) {
        if outboxState.pendingLocation == uploaded {
            outboxState.pendingLocation = nil
            drainMutatedOutbox = true
        }
        scheduleOutboxPersist()
    }

    /// Resolves a permanently rejected chunk from the FRONT of the health
    /// outbox by binary split: halves that deliver are removed, the rejection
    /// narrows to single samples, and each poison sample is dropped with its
    /// fields logged (#24a follow-up, items 2+3). Progress persists after
    /// every step, so an interruption never loses resolved work. Returns
    /// false on a transient failure — the drain stops and the remaining
    /// backlog re-attempts on the next trigger.
    private func resolveRejectedChunk(size: Int) async -> Bool {
        guard size > 0, !outboxState.pendingHealthSamples.isEmpty else { return true }

        if size == 1 {
            let poison = outboxState.pendingHealthSamples.removeFirst()
            sensorLog.error("drain: dropping poison health sample — metric=\(poison.metric, privacy: .public) value=\(poison.value, privacy: .public) unit=\(poison.unit, privacy: .public) startAt=\(poison.startAt.description, privacy: .public) endAt=\(poison.endAt?.description ?? "nil", privacy: .public)")
            // Rare recovery path: persist each step NOW (not debounced) so
            // the documented never-loses-resolved-work contract holds — a
            // crash mid-resolution must not re-run the whole 422 split.
            persistOutboxImmediately()
            return true
        }

        let firstHalf = size / 2
        for partSize in [firstHalf, size - firstHalf] {
            let part = Array(outboxState.pendingHealthSamples.prefix(partSize))
            guard !part.isEmpty else { continue }
            switch await uploadHealthTracked(part) {
            case .delivered:
                removeDeliveredHealthPrefix(part)
                persistOutboxImmediately()
            case .rejected:
                guard await resolveRejectedChunk(size: part.count) else { return false }
            case .retry, .failed:
                return false
            }
        }
        return true
    }

    private func uploadLocation(_ pending: SensorOutboxState.PendingLocation) async -> LocationUploadOutcome {
        // Reverse geocode to get a human-readable address
        let address = await reverseGeocode(latitude: pending.latitude, longitude: pending.longitude)

        let body = SensorLocationBody(
            latitude: pending.latitude,
            longitude: pending.longitude,
            altitude: pending.altitude,
            accuracy: pending.accuracy,
            address: address,
            recordedAt: iso8601Formatter.string(from: pending.recordedAt)
        )

        switch await performAuthorizedUpload(path: "device/sensor/location", body: body) {
        case .response(let result):
            guard let result else { return .failed }
            if result.wasDelivered { return .delivered }
            return result.deliveryState == "retry" ? .retry : .failed
        case .rejected:
            return .rejected
        case .transientFailure:
            return .failed
        }
    }

    private func reverseGeocode(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            if #available(iOS 26.0, *) {
                guard let request = MKReverseGeocodingRequest(location: location) else {
                    return nil
                }
                let mapItems = try await request.mapItems
                guard let item = mapItems.first else { return nil }
                if let shortAddress = item.address?.shortAddress, !shortAddress.isEmpty {
                    return shortAddress
                }
                if let fullAddress = item.address?.fullAddress, !fullAddress.isEmpty {
                    return fullAddress
                }
                if let singleLine = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true),
                   !singleLine.isEmpty {
                    return singleLine
                }
                return item.name
            } else {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                guard let place = placemarks.first else { return nil }
                let parts = [place.name, place.thoroughfare, place.locality, place.administrativeArea]
                    .compactMap { $0 }
                return parts.isEmpty ? nil : parts.joined(separator: ", ")
            }
        } catch {
            return nil
        }
    }

    private func uploadHealth(_ samples: [SensorOutboxState.PendingHealthSample]) async -> HealthUploadOutcome {
        let body = SensorHealthBody(
            samples: samples.map { sample in
                SensorHealthBody.Sample(
                    metric: sample.metric,
                    value: sample.value,
                    unit: sample.unit,
                    startAt: iso8601Formatter.string(from: sample.startAt),
                    endAt: sample.endAt.map { iso8601Formatter.string(from: $0) }
                )
            }
        )

        switch await performAuthorizedUpload(path: "device/sensor/health", body: body) {
        case .response(let result):
            guard let result else { return .failed }
            if result.wasDelivered { return .delivered }
            return result.deliveryState == "retry" ? .retry : .failed
        case .rejected(let message):
            return .rejected(message)
        case .transientFailure:
            return .failed
        }
    }

    /// One authorized POST, classified: a 401 gets one token-refresh retry; a
    /// relay 400/422 is a PERMANENT payload rejection (retrying identical
    /// bytes can never succeed); everything else — network, 5xx, failed
    /// refresh — is transient and keeps the backlog for the next drain (#24a).
    private func performAuthorizedUpload<Body: Encodable>(path: String, body: Body) async -> UploadAttempt {
        do {
            return .response(try await executeUpload(path: path, body: body, accessToken: await accessTokenProvider()))
        } catch RelayAPIClient.ClientError.unauthorized {
            sensorLog.warning("upload \(path): 401 unauthorized, attempting token refresh…")
            guard let refreshedToken = await accessTokenRefresher(), !refreshedToken.isEmpty else {
                sensorLog.error("upload \(path): token refresh failed/empty")
                return .transientFailure
            }
            do {
                return .response(try await executeUpload(path: path, body: body, accessToken: refreshedToken))
            } catch RelayAPIClient.ClientError.payloadRejected(let statusCode, let message) {
                sensorLog.error("upload \(path): permanent \(statusCode) rejection — \(message, privacy: .public)")
                return .rejected(message)
            } catch {
                sensorLog.error("upload \(path): error after refresh — \(error.localizedDescription)")
                return .transientFailure
            }
        } catch RelayAPIClient.ClientError.payloadRejected(let statusCode, let message) {
            sensorLog.error("upload \(path): permanent \(statusCode) rejection — \(message, privacy: .public)")
            return .rejected(message)
        } catch {
            sensorLog.error("upload \(path): error — \(error.localizedDescription)")
            return .transientFailure
        }
    }

    private func executeUpload<Body: Encodable>(path: String, body: Body, accessToken: String?) async throws -> DeliveryResult? {
        guard let accessToken, !accessToken.isEmpty else {
            sensorLog.warning("executeUpload \(path): no access token")
            return nil
        }
        let result: DeliveryResult = try await apiClient.post(
            path: path,
            body: body,
            accessToken: accessToken
        )
        sensorLog.notice("executeUpload \(path, privacy: .public): deliveryState=\(result.deliveryState, privacy: .public) wasDelivered=\(result.wasDelivered, privacy: .public)")
        return result
    }
}

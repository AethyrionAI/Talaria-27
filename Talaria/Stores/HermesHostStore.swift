import Foundation

enum HermesHostConnectionState: Equatable, Sendable {
    case online
    case offline
    case unreachable
    case notConnected
    /// #350: paired (or host-configured) but reachability NOT yet measured.
    /// #25 governs its rendering: no ONLINE claim, no green, anywhere.
    case checking
}

@MainActor
@Observable
final class HermesHostStore {
    var currentHost: HermesHostStatus?
    var activeEnrollmentCode: HostEnrollmentCode?
    var isLoading = false
    var isWorking = false
    var lastErrorMessage: String?
    var onHostChanged: (@MainActor () -> Void)?

    private let hostService: any HermesHostServiceProtocol
    private let accessTokenProvider: @MainActor () async -> String?
    /// #310: does the ACTIVE profile have a relay plane at all?
    ///
    /// Gated here rather than only at the activation call site, because this
    /// store's callers are not only `handleActiveProfileChanged` —
    /// `ConnectHermesHostScreen` has its own `.task { await refresh() }`, so
    /// a gate that lived at the switch alone would be bypassed the moment the
    /// user opened Pairing & Devices. Capability detection belongs to the
    /// capability, not to one of its callers.
    ///
    /// Defaults to "yes" so every existing construction is unchanged.
    private let relayAvailabilityProvider: @MainActor () -> Bool

    init(
        hostService: any HermesHostServiceProtocol,
        accessTokenProvider: @escaping @MainActor () async -> String?,
        relayAvailabilityProvider: @escaping @MainActor () -> Bool = { true }
    ) {
        self.hostService = hostService
        self.accessTokenProvider = accessTokenProvider
        self.relayAvailabilityProvider = relayAvailabilityProvider
    }

    var isHostOnline: Bool {
        currentHost?.isOnline == true
    }

    var connectionState: HermesHostConnectionState {
        if currentHost?.isOnline == true {
            return .online
        }

        if currentHost != nil {
            return lastErrorMessage == nil ? .offline : .unreachable
        }

        if lastErrorMessage != nil {
            return .unreachable
        }

        return .notConnected
    }

    /// #310: the honest empty state for a gateway-only profile. Stated
    /// rather than left silent — `currentHost == nil` with no message is
    /// indistinguishable from "asked the relay, no host enrolled", and the
    /// two lead a user to opposite actions (enrol a host vs. add a relay).
    static let relayUnavailableMessage =
        "This profile has no relay URL, so host pairing and enrollment aren't available on it."

    func refresh() async {
        guard !isLoading else { return }
        guard relayAvailabilityProvider() else {
            let hadHost = currentHost != nil
            currentHost = nil
            activeEnrollmentCode = nil
            lastErrorMessage = Self.relayUnavailableMessage
            // 🔴 FIRE THE HOOK ONLY ON AN ACTUAL TRANSITION — this line cost a
            // gate failure, and the reason is worth keeping.
            //
            // The first version of this guard called `onHostChanged?()`
            // unconditionally. That looked harmless beside the success path,
            // which also calls it every time — but the FAILURE path below
            // never called it at all, and a relay-less profile is the failure
            // case, not the success case. Meanwhile
            // `ChatScreen.monitorConnectionStatus()` polls `refresh()` on a
            // cadence for as long as the chat screen is visible, and the hook
            // (`AppContainer.swift:1258`) does real main-actor work on every
            // firing: `updateWidgetData()` writes the App Group container,
            // and it spawns a command-catalog refresh Task.
            //
            // So a gateway-only profile turned an idle chat screen into a
            // periodic burst of App Group I/O — which stalled a streaming
            // turn past its 40 s budget and failed
            // `testQueuedChipCancelRemovesHeldMessageWithNothingPosted`. The
            // unit tests missed it (they call `refresh()` once) and Release
            // built clean; only the full UI bundle caught it.
            //
            // `onHostChanged` means "the host RECORD changed". With no relay
            // the host is nil and stays nil, so announcing it on every poll
            // was wrong on its own terms, independently of the cost.
            if hadHost { onHostChanged?() }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await hostService.fetchCurrentHost(accessToken: await accessTokenProvider())
            // #136: a cancelled launch probe was superseded by a reset —
            // its result must not land over the canceller's state.
            guard !Task.isCancelled else { return }
            currentHost = fetched
            lastErrorMessage = nil
            onHostChanged?()
        } catch is CancellationError {
            // #136: cancellation is the caller superseding this probe, not
            // a host failure — don't smear an error over the reset state.
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func generateEnrollmentCode() async {
        guard !isWorking else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            activeEnrollmentCode = try await hostService.createEnrollmentCode(accessToken: await accessTokenProvider())
            currentHost = try await hostService.fetchCurrentHost(accessToken: await accessTokenProvider())
            lastErrorMessage = nil
            onHostChanged?()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func revokeCurrentHost() async {
        guard !isWorking else { return }

        isWorking = true
        defer { isWorking = false }

        do {
            try await hostService.revokeCurrentHost(accessToken: await accessTokenProvider())
            currentHost = nil
            activeEnrollmentCode = nil
            lastErrorMessage = nil
            onHostChanged?()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func reset() {
        currentHost = nil
        activeEnrollmentCode = nil
        isLoading = false
        isWorking = false
        lastErrorMessage = nil
        onHostChanged?()
    }
}

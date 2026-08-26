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
    var isLoading = false
    var lastErrorMessage: String?
    var onHostChanged: (@MainActor () -> Void)?

    private let hostService: any HermesHostServiceProtocol
    /// **#309 Lane C (row 7's adapt): the RELAY availability gate is now a
    /// GATEWAY-CREDENTIAL gate.**
    ///
    /// #310 put a gate here rather than only at the activation call site,
    /// because this store's callers are not only `handleActiveProfileChanged`
    /// — screens refresh it directly too (today `ConnectHostScreen`'s own
    /// `.task { await refresh() }`; originally the since-deleted Pairing &
    /// Devices screen, #412), so a gate that lived at the switch alone would
    /// be bypassed the moment a screen opened. That reasoning is untouched; only the
    /// capability it asks about changed, because the capability the fetch
    /// needs changed with it. Same predicate as
    /// `AppContainer.hasGatewayCredentials` (#411/Lane A), derived per call so
    /// a profile switch or a Server-settings edit changes the answer with no
    /// rewiring.
    ///
    /// Defaults to "yes" so every existing construction is unchanged.
    private let hasGatewayCredentials: @MainActor () -> Bool

    init(
        hostService: any HermesHostServiceProtocol,
        hasGatewayCredentials: @escaping @MainActor () -> Bool = { true }
    ) {
        self.hostService = hostService
        self.hasGatewayCredentials = hasGatewayCredentials
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

    func refresh() async {
        guard !isLoading else { return }
        // **#309 Lane C: the honest empty state is now `.notConnected`, with
        // NO message — and the message's deletion is the correction, not a
        // regression.**
        //
        // #310 stated a reason here (`relayUnavailableMessage`: "this profile
        // has no relay URL…") on the argument that a nil host with no message
        // is indistinguishable from "asked the relay, no host enrolled", and
        // that the two lead the user to opposite actions. That argument was
        // right about the RELAY plane, where host presence and phone pairing
        // were separate facts with separate remedies. On the gateway plane
        // they are one fact: the gateway IS the host, so "no gateway
        // credentials" and "no host" are the same state and there is no second
        // action to disambiguate. `.notConnected` already renders it —
        // "No Host / Set up from your Hermes machine" — and routing it through
        // `lastErrorMessage` would paint an unconfigured install as a BROKEN
        // one (`.unreachable`), which is the misattribution #412 filed on the
        // Inbox's twin of this gate.
        guard hasGatewayCredentials() else {
            let hadHost = currentHost != nil
            currentHost = nil
            lastErrorMessage = nil
            // 🔴 FIRE THE HOOK ONLY ON AN ACTUAL TRANSITION — this line cost a
            // gate failure, and the reason is worth keeping.
            //
            // The first version of this guard called `onHostChanged?()`
            // unconditionally. That looked harmless beside the success path,
            // which also calls it every time — but the FAILURE path below
            // never called it at all, and a credential-less profile is the
            // failure case, not the success case. Meanwhile
            // `ChatScreen.monitorConnectionStatus()` polls `refresh()` on a
            // cadence for as long as the chat screen is visible, and the hook
            // (`AppContainer.makeDefault`) does real main-actor work on every
            // firing: `updateWidgetData()` writes the App Group container,
            // and it spawns a command-catalog refresh Task.
            //
            // So a credential-less profile turned an idle chat screen into a
            // periodic burst of App Group I/O — which stalled a streaming
            // turn past its 40 s budget and failed
            // `testQueuedChipCancelRemovesHeldMessageWithNothingPosted`. The
            // unit tests missed it (they call `refresh()` once) and Release
            // built clean; only the full UI bundle caught it.
            //
            // `onHostChanged` means "the host RECORD changed". With no host
            // the record is nil and stays nil, so announcing it on every poll
            // was wrong on its own terms, independently of the cost.
            if hadHost { onHostChanged?() }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await hostService.fetchCurrentHost()
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

    // #309 Lane C: `generateEnrollmentCode()` and `revokeCurrentHost()` are
    // DELETED with rows 8 and 9. Both spoke to the relay's enrollment record —
    // a host registering with a third party so the phone could ask about it —
    // and there is no third party left: the gateway is the host. "Revoke Host"
    // on the Pairing & Devices screen went with them rather than becoming a
    // button that clears a record the very next `refresh()` re-derives.
    // Forgetting a host is local and already has an owner:
    // `PairingStore.disconnect()` (the screen's Disconnect action).

    func reset() {
        currentHost = nil
        isLoading = false
        lastErrorMessage = nil
        onHostChanged?()
    }
}

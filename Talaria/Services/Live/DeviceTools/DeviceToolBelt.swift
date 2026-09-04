import CoreLocation
import Foundation
import FoundationModels
import os
import UIKit

/// Device tool belt v1 (#28): Swift `Tool` conformances handed to the local
/// brain's `LanguageModelSession` — the device-side mirror of the Hermes MCP
/// tools. This wave is the READ set (no side effects, no confirmation gate);
/// action tools with the shared confirm gate land in #29.
///
/// Honesty rules (real-data-only): a tool that can't answer says WHY — the
/// permission isn't granted, the sensor has no data, the network is down —
/// as its tool RESULT, so the model reacts conversationally instead of the
/// turn dying. Nothing is ever fabricated on a tool's behalf.
enum DeviceToolBelt {

    /// Assembles the read belt. Providers are closures so the belt can be
    /// built before the stores it reads from (AppContainer wires them after
    /// construction, same pattern as the router's conversation lookup).
    @MainActor
    static func makeReadTools(
        relay: ToolEventRelay,
        conversationProvider: @escaping @MainActor () -> Conversation?,
        sessionCacheProvider: @escaping @MainActor () -> [ConversationSearchTool.CachedSession],
        spotlightEnabledProvider: @escaping @MainActor () -> Bool,
        // #251-2A: the app passes the provider in so the phone-query reader
        // (`LivePhoneQueryReader`) shares this exact instance — one
        // CLLocationManager per device, not one per consumer. Defaulted so
        // every existing caller (and every test) is unchanged.
        location: DeviceLocationProvider = DeviceLocationProvider()
    ) -> [any Tool] {
        [
            DeviceHealthTool(relay: relay),
            LocationTool(relay: relay, location: location),
            MotionTool(relay: relay),
            CalendarReadTool(relay: relay),
            ReminderReadTool(relay: relay),
            WeatherTool(relay: relay, location: location),
            PlacesTool(relay: relay, location: location),
            ContactsTool(relay: relay),
            DeviceStatusTool(relay: relay),
            ImageTextTool(relay: relay, conversationProvider: conversationProvider),
            BarcodeReaderTool(relay: relay, conversationProvider: conversationProvider),
            ConversationSearchTool(
                relay: relay,
                conversationProvider: conversationProvider,
                sessionCacheProvider: sessionCacheProvider,
                spotlightEnabledProvider: spotlightEnabledProvider
            ),
        ]
    }

    /// Assembles the ACTION belt (#29) — side-effecting tools, every one
    /// behind the shared ToolConfirmationCenter gate. The model can never
    /// silently mutate the phone.
    @MainActor
    static func makeActionTools(
        relay: ToolEventRelay,
        confirmations: ToolConfirmationCenter,
        alarmService: AlarmService
    ) -> [any Tool] {
        [
            ReminderCreateTool(relay: relay, confirmations: confirmations),
            CalendarEventTool(relay: relay, confirmations: confirmations),
            AlarmTool(relay: relay, confirmations: confirmations, alarmService: alarmService),
        ]
    }

    /// #200: the action-tool names as ONE list for the battery capture
    /// surfaces (the export's confirm=none synthesis, the drill-down
    /// display). Pinned against `makeActionTools` by test so it can never
    /// drift from the real belt.
    static let actionToolNames: Set<String> = ["createReminder", "createCalendarEvent", "scheduleAlarm"]

    /// The belt as it should be OFFERED for one turn (#176). Vision tools come
    /// off when the conversation carries no image at all.
    ///
    /// This is availability gating, chosen over prompt-tuning because it is
    /// structural: a tool that isn't in the session's tool list cannot be
    /// selected, however the model feels about it. The reported failure was
    /// `readImageText` firing on "Write a haiku about rain" — the belt handed
    /// the model an OCR tool and there was nothing to read.
    ///
    /// Everything else passes through in place. The four health/motion calls
    /// seen on the same session were APPROPRIATE; this narrows selection, it
    /// does not redesign the belt.
    static func offeredTools(from belt: [any Tool], hasImageInContext: Bool) -> [any Tool] {
        guard !hasImageInContext else { return belt }
        return belt.filter { !($0 is any ImageDependentTool) }
    }
}

// MARK: - Context-conditioned tools

/// A tool that can only do its job when the conversation carries an image
/// (#176). `DeviceToolBelt.offeredTools` withholds these when there is
/// nothing to look at.
protocol ImageDependentTool {}

// MARK: - Tool event relay

/// Bridges FoundationModels tool invocations onto the existing
/// `StreamingUpdate.toolActivity` channel, so the #10/#11 tool-chip UI
/// renders local tool calls with zero ChatStore changes. The local backend
/// points `emit` at the live stream's continuation for the duration of a
/// turn; between turns it's nil and events drop harmlessly.
@MainActor
final class ToolEventRelay {
    var emit: ((ToolCallEvent) -> Void)?

    #if DEBUG
    /// #196 battery: when non-nil, EVERY tool start logs a classifiable
    /// notice carrying this trial tag — read tools included, which the
    /// confirmation gate never sees. (The first battery's blind spot: two
    /// trials leaked ConversationSearch output into replies with no log
    /// line anywhere.) Nil in every normal run; the battery sets it per
    /// trial and clears it at the end of the run.
    static var batteryTrialTag: String?
    private static let batteryLogger = Logger(subsystem: "org.aethyrion.talaria", category: "LocalChatBackend")
    #endif

    /// #225: the per-turn bound. Nil leaves every call admitted, which is what
    /// bare test belts and any caller that never sets one get.
    var governor: ToolCallGovernor?

    /// #228 (Lane 0.1): the production instrument's data source. Admitted
    /// starts and governor refusals, counted per turn — the numbers the
    /// verbose log lines carry, and what replaces counting chips by eye.
    private(set) var executedCallsThisTurn = 0
    private(set) var refusalsThisTurn = 0

    /// #233: conversation-scoped — deliberately NOT reset in beginTurn(),
    /// because the ask/answer round-trip spans two turns. Cleared only by
    /// endConversationToolState() (fresh chat) and process launch.
    private(set) var earlyMorningAskIssued = false

    /// #233: true exactly once per conversation. The reminder tool bounces
    /// on true and proceeds on false — so a user-confirmed "yes, 4 AM"
    /// re-call cannot loop, and a model that ignores the ask degrades to
    /// staging the card, where the caution row is the backstop.
    func claimEarlyMorningAsk() -> Bool {
        if earlyMorningAskIssued { return false }
        earlyMorningAskIssued = true
        return true
    }

    /// #249: conversation-scoped like the wee-hour latch — the past-due
    /// bounce's ask/answer round-trip spans turns too.
    private(set) var pastDueAskIssued = false

    /// #249: the evening-clock ask's latch, same lifetime.
    private(set) var eveningClockAskIssued = false

    /// #249: true exactly once per conversation — the past-due bounce.
    func claimPastDueAsk() -> Bool {
        if pastDueAskIssued { return false }
        pastDueAskIssued = true
        return true
    }

    /// #249: true exactly once per conversation — the evening-clock ask.
    func claimEveningClockAsk() -> Bool {
        if eveningClockAskIssued { return false }
        eveningClockAskIssued = true
        return true
    }

    /// #338 — conversation-scoped, the same lifetime as the #233/#249 latches
    /// above and reset in the same one place.
    ///
    /// **Why the honesty guard needs a CONVERSATION fact and not just a turn
    /// fact.** The guard's one input was this turn's executed calls, so the
    /// commonest honest exchange in the app fired it: the user taps Confirm on
    /// turn 1 (the reminder is really written) and asks *"did that go
    /// through?"* on turn 2 — a turn with zero tool calls by construction. The
    /// honest answer *"Yes, the reminder is set for 8 PM"* then collected the
    /// correction *"Nothing was created."*
    ///
    /// **What this flag does and does NOT mean.** It means an action tool
    /// STARTED — i.e. a real confirmation card was staged. It does not mean the
    /// user accepted it, because `started` is emitted before the confirmation
    /// is awaited. That is deliberately the same approximation bar 338-D
    /// already makes for the current turn; widening the guard past it would
    /// need the confirmation outcome, which is a different lane.
    private(set) var actionToolExecutedThisConversation = false

    /// #233: the conversation-boundary reset. Turn-scoped state belongs in
    /// beginTurn(); anything conversation-scoped resets here instead.
    func endConversationToolState() {
        earlyMorningAskIssued = false
        pastDueAskIssued = false
        eveningClockAskIssued = false
        // #338: a fresh conversation has no earlier turn to license anything.
        actionToolExecutedThisConversation = false
    }

    /// #228: NOT `#if DEBUG` — #218's lesson is that an all-Debug stack is
    /// blind to what Release does, and Release is what a user runs. Same
    /// subsystem/category as the battery lines so one Console filter
    /// (`org.aethyrion.talaria`, LocalChatBackend) captures a whole turn.
    private static let instrumentLogger = Logger(subsystem: "org.aethyrion.talaria", category: "LocalChatBackend")

    /// #340 bar 340-U-B — the user's own message for the CURRENT turn, or nil.
    ///
    /// **Why the belt needs this at all.** A tool sees only what the MODEL sent
    /// it. When `createReminder` arrives with an empty `due`, the time the user
    /// actually said ("remind me at 4") is nowhere in the tool's arguments, so
    /// there is nothing to resolve a date from. This is the one channel that
    /// carries the sentence itself down to where `DeviceActionParsing.detectDue`
    /// can read it.
    ///
    /// **It is the USER's text, never the assembled prompt.** By the time a turn
    /// reaches `beginToolTurn()` the prompt has grown a memory prefix and any
    /// instruction preamble; mining THAT for a date would let a remembered
    /// sentence set the due time of an unrelated reminder. Both production call
    /// sites pass `message`, pinned by source witness in
    /// `ToolTurnUserTextTests`.
    ///
    /// **Turn-scoped, and structurally so.** It is set by the ONE call that
    /// already opens every turn, and the parameter's `nil` default means a
    /// caller that passes nothing CLEARS it rather than inheriting the last
    /// turn's sentence. That is deliberate rather than incidental: #343's
    /// governor bug was exactly a per-turn field that leaked because it was
    /// reset somewhere other than the turn boundary, and the DEBUG instruments
    /// call the bare `beginTurn()` dozens of times in a row.
    private(set) var currentTurnUserText: String?

    #if DEBUG
    /// #340 bar 340-U-D — the `armed-nofallback` arm's ONLY delta from
    /// production, and it is one Bool.
    ///
    /// **Why a flag rather than a fifth tool struct.** Every other reminder
    /// treatment cell swaps in a `ReminderCreateTool…` copy, and each of those
    /// copies carries the model-facing TEXT it was made for while sharing
    /// `performCreate`'s one engine — *"two structs, one engine"*. This arm's
    /// delta is not text at all; it is a term INSIDE that engine. A copy would
    /// have had to fork the engine, which is the one thing the copy discipline
    /// exists to prevent, and the retired `armed-bareclock` copy is this lane's
    /// own record of what a fork costs once production moves on beneath it.
    ///
    /// **Why on the relay.** The relay already carries per-turn state into the
    /// belt (`currentTurnUserText`, the governor), `performCreate` already
    /// holds one, and it is already MainActor — so the battery can arm it at
    /// the turn boundary in the same breath as `beginTurn`, and the engine
    /// reads it exactly where the fallback lives.
    ///
    /// **DEBUG-only, and `false` by default.** A default of `true` would ship
    /// the product with the fix switched off; the `#if DEBUG` is what makes
    /// "production cannot reach this" a compile-time fact rather than a
    /// convention. A Release build proves the tree COMPILES — it does not
    /// prove the symbol is unreachable, since code outside a guard would
    /// compile perfectly well and simply ship — so
    /// `everyMentionOfTheSwitchSitsInsideADebugRegion` reads every Swift file
    /// under `Talaria/` and fails if any mention escapes a guard.
    ///
    /// **PER-TURN STATE: `beginTurn` clears it, exactly like
    /// `currentTurnUserText` above.** This paragraph used to say the opposite —
    /// that the reset was unnecessary because the battery writes the switch on
    /// every trial from the cell — and that argument was true but too narrow.
    /// It covers leaks between CELLS and nothing else. `ToolEventRelay` is ONE
    /// instance per `AppContainer`, shared by production chat and by every
    /// other instrument in the launch, and `.armedNofallback` is the LAST
    /// default due-date cell: so the terminal state of every default run was
    /// `true`, and it stayed `true` for the rest of the process. A later
    /// shape/refusal/read-tool run created its reminders with the fix off, and
    /// a hand check of the fallback in chat read as a product regression.
    ///
    /// Clearing it at the turn boundary is what makes the leak unreachable:
    /// every production turn and every instrument's bare `beginTurn()` closes
    /// it, and the battery's own per-trial write lands AFTER `beginTurn`, so
    /// the arming still wins for the trial it was written for. That ordering
    /// is the load-bearing part and it is pinned
    /// (`anArmedTrialAfterANofallbackTrialStillStagesTheDate`).
    ///
    /// `runActionBattery` clears it again at the run's end, beside the
    /// `batteryTrialTag` clear — for the warm-up trial, which opens no turn at
    /// all, and for a run that dies mid-cell.
    var disableUserTextDueFallback = false
    #endif

    /// The single turn-boundary call (#225 + #228 + #340): resets the
    /// instrument's counters and the governor's budget together, so the log's
    /// running index and the admission decisions can never describe different
    /// turns — and installs (or clears) this turn's user text.
    ///
    /// `userText` is defaulted so every existing caller — the per-trial
    /// `beginTurn()` the DEBUG instruments make (#343) — compiles and behaves
    /// exactly as before, with the field explicitly cleared.
    func beginTurn(userText: String? = nil) {
        executedCallsThisTurn = 0
        refusalsThisTurn = 0
        currentTurnUserText = userText
        #if DEBUG
        // #340 bar 340-U-D: the measurement switch is per-turn state like the
        // field above it, so it clears at the same boundary. The battery's
        // per-trial arming is written AFTER this call and therefore still
        // wins for its own trial; what this closes is the switch surviving
        // the battery altogether onto production chat and every later
        // instrument in the launch. See the declaration.
        disableUserTextDueFallback = false
        #endif
        governor?.beginTurn()
    }

    /// #228 log-line shapes — pure and pinned by test, because they are the
    /// grep keys a device-run log gets read by. `.notice`, never `.debug`:
    /// Console.app's default view suppresses `.info` and below.
    nonisolated static func callLogLine(sequence: Int, name: String, detail: String?) -> String {
        var line = "tool-call #\(sequence) \(name)"
        if let detail, !detail.isEmpty {
            line += " — \(detail.prefix(80))\(detail.count > 80 ? "…" : "")"
        }
        return line + " (#228)"
    }

    nonisolated static func refusalLogLine(name: String, executedThisTurn: Int, refusalsThisTurn: Int) -> String {
        "tool-call REFUSED \(name) — \(executedThisTurn) executed, \(refusalsThisTurn) refusal(s) this turn (#225/#228)"
    }

    /// Announces a tool call AND decides whether it may proceed (#225).
    ///
    /// **The admission check runs FIRST, before any event is emitted.** A
    /// refused call must not produce a `started` chip in the transcript or a
    /// battery line — both would record work that never happened, and a tool
    /// chip for a call that did not run is exactly the kind of lie #180 is
    /// about.
    ///
    /// Callers return the refusal string as their own output. **Never throw
    /// it:** a throw kills the turn above the model (#197's mechanism) and
    /// would trade an unbounded spiral for a dead turn.
    @discardableResult
    func started(_ name: String, detail: String? = nil) throws -> ToolCallGovernor.Admission {
        if let governor {
            let admission = governor.admit(tool: name)
            if case .refused = admission {
                // #232: refusals past the threshold end the tool phase
                // STRUCTURALLY — 57 string-refusals in one instrumented turn
                // proved the model treats them as results to argue with. The
                // count is checked BEFORE incrementing so refusals 1…threshold
                // stay strings and attempt threshold+1 throws.
                if refusalsThisTurn >= ToolPhaseCutError.refusalThreshold {
                    throw ToolPhaseCutError()
                }
                // #228 (L0-B): the refusal deliberately emits no chip, so this
                // line is the ONLY place a refused call is visible at all.
                refusalsThisTurn += 1
                if TalariaLog.isVerbose {
                    Self.instrumentLogger.notice("\(Self.refusalLogLine(name: name, executedThisTurn: self.executedCallsThisTurn, refusalsThisTurn: self.refusalsThisTurn), privacy: .public)")
                }
                return admission
            }
        }
        executedCallsThisTurn += 1
        // #338: the conversation-scoped latch, set at the ONE place an admitted
        // call is counted — so it can never disagree with the per-turn count.
        if DeviceToolBelt.actionToolNames.contains(name) {
            actionToolExecutedThisConversation = true
        }
        if TalariaLog.isVerbose {
            Self.instrumentLogger.notice("\(Self.callLogLine(sequence: self.executedCallsThisTurn, name: name, detail: detail), privacy: .public)")
        }
        #if DEBUG
        if let tag = Self.batteryTrialTag {
            // One emit path for every battery line (#196 battery 4):
            // os_log + flushed stdout + the container file sink.
            LocalChatBackend.batteryEmit("battery: tool=\(name) \(tag) detail=\(String((detail ?? "").prefix(80)))")
            // Results-page store gets the UNTRUNCATED detail — the 80-char
            // prefix above is Console-line width, not a capture budget.
            LocalChatBackend.batteryRecorder.recordToolCall(name: name, detail: detail ?? "")
        }
        #endif
        emit?(ToolCallEvent(name: name, phase: .started, detail: detail))
        return .allowed
    }

    /// #212: `result` is what the tool RETURNED, recorded into the battery
    /// store only. It never reaches the transcript or the UI — the completed
    /// event is unchanged — so this cannot leak internals into a reply the way
    /// #197's tool dump did.
    func completed(_ name: String, result: String? = nil) {
        #if DEBUG
        if Self.batteryTrialTag != nil, let result {
            LocalChatBackend.batteryRecorder.recordToolResult(name: name, result: result)
        }
        #endif
        emit?(ToolCallEvent(name: name, phase: .completed))
    }
}

// MARK: - Shared one-shot location

/// One CLLocationManager shared by the location-flavored tools (location /
/// weather / places). Requests when-in-use authorization on FIRST USE —
/// that's #31's contextual priming: the permission prompt appears while the
/// user is asking a location question, never in an up-front wall.
@MainActor
final class DeviceLocationProvider: NSObject, CLLocationManagerDelegate {

    /// #203 (2A): the seam. Everything the waiting policies ask of
    /// CoreLocation, as MainActor closures — production wires all four to one
    /// concrete CLLocationManager; tests wire them to a script. The policies
    /// themselves (the fix deadline + generation counting, the
    /// dismissed-dialog foreground trigger, the unbounded human wait) sit
    /// above this line, which is what makes them drivable from a test at
    /// all. Closures rather than a protocol for the same reason the belt's
    /// providers are closures — and so the non-Sendable manager stays
    /// captured inside them, never crossing a concurrency boundary.
    struct Seam {
        var authorizationStatus: @MainActor () -> CLAuthorizationStatus
        var cachedLocation: @MainActor () -> CLLocation?
        var requestWhenInUseAuthorization: @MainActor () -> Void
        var requestLocation: @MainActor () -> Void
    }

    private let seam: Seam
    private let notificationCenter: NotificationCenter
    /// The deadline THIS instance arms. Production always gets
    /// `Self.fixDeadline`; tests shorten it to prove the deadline path fires.
    private let fixDeadline: Duration
    private var authorizationContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []
    private var locationContinuations: [CheckedContinuation<CLLocation?, Never>] = []
    /// #203: bumped every time waiters are resolved, so a fired deadline can
    /// only ever affect the request it was armed for.
    private var locationGeneration = 0
    /// #203 (2A): armed only while an authorization prompt is pending. Read
    /// access is internal so the teardown tests can see it; only this class
    /// writes it.
    private(set) var foregroundObserver: NSObjectProtocol?

    /// Production wiring: one concrete CLLocationManager behind the seam,
    /// this object as its delegate. This initializer is the one line of the
    /// class no unit test can reach — everything behind it is driven through
    /// the same entry points CoreLocation uses.
    override convenience init() {
        let manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.init(seam: Seam(
            authorizationStatus: { manager.authorizationStatus },
            cachedLocation: { manager.location },
            requestWhenInUseAuthorization: { manager.requestWhenInUseAuthorization() },
            requestLocation: { manager.requestLocation() }
        ))
        manager.delegate = self
    }

    init(
        seam: Seam,
        notificationCenter: NotificationCenter = .default,
        fixDeadline: Duration = DeviceLocationProvider.fixDeadline
    ) {
        self.seam = seam
        self.notificationCenter = notificationCenter
        self.fixDeadline = fixDeadline
        super.init()
    }

    /// Settled authorization status, prompting if not yet determined.
    ///
    /// #203 (2A, Owen's call 2026-07-31): still UNBOUNDED by any clock — a
    /// machine deadline on a human reading a system dialog is unfair, and
    /// that reasoning stands. What is NOT fair is parking forever when the
    /// human has visibly walked away: `locationManagerDidChangeAuthorization`
    /// returns early while the status is `.notDetermined`, so a dialog
    /// dismissed WITHOUT an answer left the waiter pending with no
    /// resolution path and the turn spun.
    ///
    /// The trigger is the FOREGROUND TRANSITION, not a timer: if the app
    /// comes back with the status still undetermined, the user dismissed the
    /// dialog. The waiter resolves `.notDetermined`, every caller already
    /// renders that honestly as location-unavailable, and the turn finishes
    /// with a sentence instead of a hang — the shape #202D promoted.
    func ensureAuthorization() async -> CLAuthorizationStatus {
        let status = seam.authorizationStatus()
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            observeForegroundForDismissedDialog()
            seam.requestWhenInUseAuthorization()
        }
    }

    /// One observer per pending prompt. Resolving is idempotent — the
    /// delegate may also fire, and whichever lands first empties the queue.
    private func observeForegroundForDismissedDialog() {
        guard foregroundObserver == nil else { return }
        foregroundObserver = notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resolveAuthorizationIfDialogWasDismissed() }
        }
    }

    func resolveAuthorizationIfDialogWasDismissed() {
        if let foregroundObserver {
            notificationCenter.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
        // Only a still-undetermined status means the dialog was dismissed
        // without an answer. A real decision resolves through the delegate.
        guard seam.authorizationStatus() == .notDetermined else { return }
        let waiting = authorizationContinuations
        authorizationContinuations = []
        waiting.forEach { $0.resume(returning: .notDetermined) }
    }

    /// How long a one-shot fix may take before the tools give up. Apple's
    /// `requestLocation()` normally delivers a fix or an error well inside
    /// this; the deadline exists for when it delivers NEITHER.
    static let fixDeadline: Duration = .seconds(10)

    /// One-shot fix. A fix from the last two minutes is fresh enough for
    /// weather/places and skips the radio spin-up.
    ///
    /// #203 (SHIP BLOCKER, Hermes audit): this used to park a continuation with
    /// NO deadline. If CoreLocation delivered neither `didUpdateLocations` nor
    /// `didFailWithError` — plausible under beta thermal pressure — the waiter
    /// never resumed, and because a hung TOOL is not cancellable (#200Y) and the
    /// PRODUCTION stream loop has no guillotine (that is battery-only), the
    /// user's chat turn spun forever with no recovery. Now bounded: on deadline
    /// the waiters resume `nil`, which every caller already renders honestly as
    /// "couldn't get a location fix right now".
    ///
    /// `ensureAuthorization()` is deliberately left UNBOUNDED: it waits on a
    /// human reading a system dialog, and no machine deadline is fair to that.
    func currentLocation() async -> CLLocation? {
        if let cached = seam.cachedLocation(), cached.timestamp.timeIntervalSinceNow > -120 {
            return cached
        }
        let generation = locationGeneration
        let deadline = fixDeadline
        // #198: no `await` on the resolve call. This class is @MainActor, so
        // the unstructured Task inherits that isolation and the hop the `await`
        // implied never happens — the compiler flags it, and leaving it in
        // misdescribes the concurrency model to the next reader.
        Task { [weak self] in
            try? await Task.sleep(for: deadline)
            self?.failLocationWaitersIfStillPending(generation: generation)
        }
        return await withCheckedContinuation { continuation in
            locationContinuations.append(continuation)
            seam.requestLocation()
        }
    }

    /// Resumes any waiter still parked from `generation` with nil. Generation
    /// counting is what keeps a late deadline from cancelling a LATER request's
    /// waiters — the bug a naive timeout would introduce. Internal (not
    /// private) so tests can fire a STALE deadline deterministically instead
    /// of racing real timers.
    func failLocationWaitersIfStillPending(generation: Int) {
        guard generation == locationGeneration, !locationContinuations.isEmpty else { return }
        let waiting = locationContinuations
        locationContinuations = []
        locationGeneration += 1
        waiting.forEach { $0.resume(returning: nil) }
    }

    /// The MainActor half of `locationManagerDidChangeAuthorization`, split
    /// out so tests drive a real decision through the same code CoreLocation
    /// does. A decided status resolves every waiter and tears down the
    /// dismissed-dialog observer; `.notDetermined` is not a decision.
    func handleAuthorizationChange() {
        let status = seam.authorizationStatus()
        guard status != .notDetermined else { return }
        if let observer = foregroundObserver {
            notificationCenter.removeObserver(observer)
            foregroundObserver = nil
        }
        let waiting = authorizationContinuations
        authorizationContinuations = []
        waiting.forEach { $0.resume(returning: status) }
    }

    /// The MainActor half of both fix-delivery callbacks: an answer — a fix,
    /// or nil for a definitive failure — resolves every parked waiter and
    /// bumps the generation so any still-armed deadline goes stale.
    func resolveLocationWaiters(with location: CLLocation?) {
        let waiting = locationContinuations
        locationContinuations = []
        locationGeneration += 1
        waiting.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.handleAuthorizationChange() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let newest = locations.last
        Task { @MainActor in self.resolveLocationWaiters(with: newest) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resolveLocationWaiters(with: nil) }
    }
}

// MARK: - Shared formatting

/// Pure formatting helpers shared across the belt — kept static + Foundation
/// only so they're unit-testable without any framework entitlements.
enum DeviceToolFormat {

    /// "7h 24m" from fractional hours.
    static func hoursMinutes(fromHours hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "512 MB free of 128 GB" — nil-safe on either side.
    static func storageLine(availableBytes: Int64?, totalBytes: Int64?) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let free = availableBytes.map { formatter.string(fromByteCount: $0) } ?? "unknown"
        guard let totalBytes else { return "Storage: \(free) free" }
        return "Storage: \(free) free of \(formatter.string(fromByteCount: totalBytes))"
    }

    /// Compact one-line snippet around the first case-insensitive match of
    /// `term` in `text` — the conversation-search result surface. Nil when
    /// the term doesn't occur.
    static func snippet(around term: String, in text: String, radius: Int = 60) -> String? {
        guard let range = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }
        let start = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var line = String(text[start ..< end])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if start > text.startIndex { line = "…" + line }
        if end < text.endIndex { line += "…" }
        return line
    }
}

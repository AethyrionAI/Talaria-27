import Foundation
import FoundationModels
import UIKit

// #388: the beta5 Apple-Intelligence SURFACE probe — what the two tiers can
// actually do, whether quota tracking is wired up at all, and whether three
// never-examined frameworks load on the device.
//
// It sits beside `+Preflight.swift`'s #335 instruments and shares their
// contract (open a recorder run, record every row INCLUDING the ones that
// measured nothing, close the run on every path) but answers a different kind
// of question: those price a PAYLOAD against the tokenizer, this one reads
// CAPABILITY. Nothing here generates, nothing is written, no tool is
// registered and no confirmation is reachable.
//
// **The rule this file is built around is `21F0C10D`'s, and #388-C states it
// for this instrument specifically: a reading the environment cannot take is
// NOT MEASURED, never a false.** On the simulator `pccGrantConfirmed` is
// false, so every PCC row here records `errors` equal to what it tried to read
// and OMITS the per-capability metrics entirely — a `vision: 0` on a sim row
// would be indistinguishable from a device row where PCC genuinely lacks
// vision, which is precisely the finding the band exists to produce. Every row
// also carries its `environment`, so a sim reading cannot be quietly folded in
// downstream (bar 388-C).
#if DEBUG
extension LocalChatBackend {

    // MARK: - #388 shared

    /// The four members of `LanguageModelCapabilities.Capability`, paired with
    /// the names they are reported under.
    ///
    /// `Capability` is a `Sendable, Hashable` struct with static members and
    /// **no `description`** — read from the beta5 `.swiftinterface`, not
    /// recalled — so a probe that wants to say which one it read has to carry
    /// the name itself. Pinned in one place so the four names in the artifact,
    /// the four in the log line and the four in the tests are the same four.
    nonisolated static let probedCapabilities:
        [(name: String, capability: LanguageModelCapabilities.Capability)] = [
            ("vision", .vision),
            ("toolCalling", .toolCalling),
            ("reasoning", .reasoning),
            ("guidedGeneration", .guidedGeneration),
        ]

    /// Bar 388-C, made structural rather than remembered: the environment is
    /// stamped on every row this instrument writes.
    nonisolated static var probeEnvironment: String {
        #if targetEnvironment(simulator)
        return "simulator"
        #else
        return "device"
        #endif
    }

    /// The reason a PCC row could not be taken here, or `nil` if it can.
    ///
    /// One function so the capability band and the quota band cannot disagree
    /// about whether the tier was readable — and so the artifact says WHY in
    /// the same words both times.
    ///
    /// `@MainActor` because `pccGrantConfirmed` is: it is a static on a
    /// `@MainActor` type, so the gate and everything that reads it share the
    /// actor. Marking this `nonisolated` compiles only by not reading the
    /// gate, which would make the refusal text and the gate two facts instead
    /// of one.
    @MainActor static var privateCloudProbeRefusal: String? {
        guard pccGrantConfirmed else {
            return "pccGrantConfirmed=false — this binary carries no entitlement (\(probeEnvironment)); NOT MEASURED, not absent"
        }
        return nil
    }

    /// The system log line #388-B asks to correlate the quota reading against.
    ///
    /// **The instrument cannot read the device's system log**, so it does not
    /// pretend to have done the correlation: it records the exact grep the
    /// operator runs next, in the artifact, beside the reading it belongs to.
    /// A note naming the missing half is honest; a metric claiming the
    /// correlation would not be.
    nonisolated static let quotaTrackerLogNeedle = "Usage limit status tracker delegate is nil"

    /// The three frameworks #388-D names, by the path `dlopen` takes.
    ///
    /// **`dlopen` rather than `import`, and the reason is a hazard not a
    /// preference.** An `import` makes the framework a LAUNCH dependency of
    /// every debug build — #324 proved a missing/incompatible symbol in that
    /// position kills the app at dyld launch with no crash log — which is a
    /// large risk to carry for one reconnaissance row. `dlopen` asks the same
    /// question at runtime and answers it with a null pointer instead of a
    /// dead process.
    ///
    /// It also answers the RIGHT question. #388-D's own words: *"Presence in
    /// the SDK is not availability."* A path that resolves in the iOS SDK on
    /// this Mac says nothing about Owen's phone; a `dlopen` that succeeds on
    /// the phone is a fact about the phone.
    nonisolated static let probedFrameworkPaths: [(name: String, path: String)] = [
        ("ImagePlayground", "/System/Library/Frameworks/ImagePlayground.framework/ImagePlayground"),
        ("VisualIntelligence", "/System/Library/Frameworks/VisualIntelligence.framework/VisualIntelligence"),
        ("MediaIntelligence", "/System/Library/Frameworks/MediaIntelligence.framework/MediaIntelligence"),
    ]

    /// One framework-load attempt: did it load, and if not, why.
    typealias FrameworkLoader = @Sendable (String) -> (loaded: Bool, error: String?)

    /// The real loader — and the seam that keeps the UNIT SUITE out of it.
    ///
    /// **🔴 This is not test-convenience plumbing. It is a side effect the
    /// suite must not carry, and it was found by measurement rather than by
    /// review.** The first version called `dlopen` unconditionally, so the
    /// seven run-level tests loaded three system frameworks into the SHARED
    /// test-host process — permanently, for every test scheduled after them,
    /// with ImagePlayground alone dragging in PencilKit and a SwiftUI stack.
    /// That run's gate went red on
    /// `foregroundWritesWidgetSnapshotEvenWhenTheNetworkChainNeverCompletes`,
    /// a timing-sensitive test in another file, while the same gate on clean
    /// `main` minutes earlier was GREEN at 2392/14.
    ///
    /// **A probe that changes the process it is measured in is not a probe.**
    /// The reconnaissance value of this band is a DEVICE fact; nothing about
    /// it needs the unit suite to actually load anything.
    ///
    /// The seam also buys the tests something the real loader never could:
    /// **the not-loaded branch**, which is unreachable on a machine where all
    /// three frameworks are present.
    ///
    /// The real path is not left unexercised — it ran on `CC-lane-1` on
    /// 2026-08-21 before this seam existed and its output is recorded in
    /// OPEN_ITEMS #388 (ImagePlayground ✅, MediaIntelligence ✅,
    /// VisualIntelligence ❌ with a sim-root `dlerror`) — and it is the
    /// default every non-test caller gets.
    nonisolated static let dlopenFrameworkLoader: FrameworkLoader = { path in
        if dlopen(path, RTLD_LAZY) != nil { return (true, nil) }
        let message = dlerror().map { String(String(cString: $0).prefix(200)) }
        return (false, message)
    }

    // MARK: - #388: `pcc-surface`

    /// **#388 bars A, B and D in one launch-armed pass.**
    ///
    /// Three bands, in this order:
    ///
    /// 1. **`capabilities`** (388-A) — `.contains(.vision / .toolCalling /
    ///    .reasoning / .guidedGeneration)` for `SystemLanguageModel.default`
    ///    and for `PrivateCloudComputeLanguageModel()`, plus each tier's
    ///    `contextSize`. **The CONTRAST is the finding, not either row
    ///    alone**, which is why both rows are written even when one of them
    ///    could not be taken — a band with one row cannot be compared, and a
    ///    band with a silently-dropped row looks complete.
    ///    - The live stake: the session is built `tools: offered` on the
    ///      assumption PCC can call them, and all three PCC turns so far
    ///      routed toolless, so `.toolCalling` on the PCC row is currently
    ///      **unevidenced in both directions**.
    /// 2. **`quota`** (388-B) — `status`, `isApproachingLimit`, `resetDate`,
    ///    `limitIncreaseSuggestion != nil`, read `repeats` times so `distinct`
    ///    is recorded rather than assumed. **The band cannot conclude
    ///    "inert"** — that verdict needs the system log line this instrument
    ///    cannot see, so the needle for it is recorded in the row's notes and
    ///    the conclusion is left to the operator who has both halves.
    /// 3. **`frameworks`** (388-D) — does each of the three load on THIS
    ///    device. The entitlement and use-case halves of 388-D are SDK reads
    ///    and live in the tracker entry, labelled as such; this band answers
    ///    only the half a device can answer.
    ///
    /// Ordering is not load-bearing here — nothing generates and no
    /// `tokenCount` is in flight, so the #335 file's "generating band last"
    /// rule has nothing to order. The bands run in bar order for readability.
    func runPCCSurfaceProbe(
        trials: Int,
        frameworkLoader: FrameworkLoader = LocalChatBackend.dlopenFrameworkLoader
    ) async {
        guard await Self.beginBatteryRun() else {
            Self.batteryEmit("battery: REFUSED — another battery is already running (#200B mutex)")
            return
        }
        defer { Self.endBatteryRun() }
        let repeats = max(1, trials)
        let environment = Self.probeEnvironment
        Self.batteryEmit("surface: PCC SURFACE START repeats=\(repeats) env=\(environment) (#388)")
        Self.batteryRecorder.beginRun(
            trialsPerCell: repeats,
            cells: ["capabilities", "quota", "frameworks"],
            kind: "pcc-surface")

        recordOnDeviceCapabilityRow()
        await recordPrivateCloudCapabilityRow()
        await recordQuotaRow(repeats: repeats)
        recordFrameworkRows(using: frameworkLoader)

        Self.batteryEmit("surface: PCC SURFACE DONE env=\(environment) (#388)")
        Self.batteryRecorder.endRun()
    }

    // MARK: - Band 1: capabilities (388-A)

    /// The on-device row. Always measurable — `SystemLanguageModel` needs no
    /// entitlement — so this row is the band's control in the literal sense:
    /// if it is missing, the band failed for a reason that has nothing to do
    /// with PCC.
    private func recordOnDeviceCapabilityRow() {
        let capabilities = model.capabilities
        var metrics: [String: Double] = ["contextSize": Double(model.contextSize)]
        var present: [String] = []
        for entry in Self.probedCapabilities {
            let has = capabilities.contains(entry.capability)
            metrics[entry.name] = has ? 1 : 0
            if has { present.append(entry.name) }
        }
        metrics["capabilityCount"] = Double(present.count)
        metrics["scored"] = Double(Self.probedCapabilities.count)
        metrics["errors"] = 0
        emitAndRecordCapabilityRow(
            variant: "on-device", metrics: metrics,
            notes: ["environment": Self.probeEnvironment,
                    "present": present.isEmpty ? "none" : present.joined(separator: "+"),
                    "variantName": model.variant.displayName],
            present: present.count, errors: 0)
    }

    /// The PCC row — and the one #388-C is about.
    ///
    /// On a simulator this cannot be read at all, and the row says so with
    /// `errors == 4` and **no per-capability metrics**. Writing zeros here
    /// would manufacture the exact finding the band exists to test for.
    private func recordPrivateCloudCapabilityRow() async {
        let probed = Self.probedCapabilities.count
        if let refusal = Self.privateCloudProbeRefusal {
            emitAndRecordCapabilityRow(
                variant: "private-cloud",
                metrics: ["scored": 0, "errors": Double(probed)],
                notes: ["environment": Self.probeEnvironment, "notMeasured": refusal],
                present: 0, errors: probed)
            return
        }
        let pcc = PrivateCloudComputeLanguageModel()
        let capabilities = pcc.capabilities
        var metrics: [String: Double] = [:]
        var present: [String] = []
        for entry in Self.probedCapabilities {
            let has = capabilities.contains(entry.capability)
            metrics[entry.name] = has ? 1 : 0
            if has { present.append(entry.name) }
        }
        metrics["capabilityCount"] = Double(present.count)
        metrics["scored"] = Double(probed)
        metrics["errors"] = 0
        metrics["isAvailable"] = pcc.isAvailable ? 1 : 0
        var notes = ["environment": Self.probeEnvironment,
                     "present": present.isEmpty ? "none" : present.joined(separator: "+"),
                     "availability": String(describing: pcc.availability)]
        // `contextSize` is `async throws` on PCC and plain on the on-device
        // model, so it cannot ride the same read. A throw is recorded as a
        // NOTE rather than folded into `errors`: the capability read
        // succeeded, and merging the two would make a network hiccup look
        // like four unread capabilities.
        do {
            metrics["contextSize"] = Double(try await privateCloudContextSize(pcc))
        } catch {
            notes["contextSizeError"] = String(String(describing: error).prefix(200))
        }
        emitAndRecordCapabilityRow(variant: "private-cloud", metrics: metrics,
                                   notes: notes, present: present.count, errors: 0)
    }

    /// `contextSize` is `get async throws` on `PrivateCloudComputeLanguageModel`
    /// (beta5 `.swiftinterface`) and plain `Int` on `SystemLanguageModel`.
    /// Wrapped so the caller reads as one line and the asymmetry is stated
    /// once, here, rather than inferred at the call site.
    private func privateCloudContextSize(_ pcc: PrivateCloudComputeLanguageModel) async throws -> Int {
        try await pcc.contextSize
    }

    /// One shape for both capability rows, so the tier they describe is the
    /// only difference between them.
    ///
    /// **`correct` = capabilities PRESENT, `trials` = capabilities PROBED.**
    /// Stated here because the ratio is not an accuracy — a 2/4 row is not a
    /// half-right measurement, it is a tier with two of four capabilities —
    /// and a reader who assumes the usual meaning would read a correct row as
    /// a broken one.
    private func emitAndRecordCapabilityRow(variant: String, metrics: [String: Double],
                                            notes: [String: String],
                                            present: Int, errors: Int) {
        Self.batteryEmit("surface: [capabilities] \(variant) present=\(present)/\(Self.probedCapabilities.count) errors=\(errors) metrics=\(metrics.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")) notes=\(notes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","))")
        Self.batteryRecorder.recordProbe(
            probe: "LanguageModelCapabilities.contains for \(variant)",
            expected: true, correct: present, trials: Self.probedCapabilities.count,
            variant: variant, band: "capabilities", errors: errors,
            metrics: metrics, notes: notes)
    }

    // MARK: - Band 2: quota (388-B)

    /// Reads `quotaUsage` `repeats` times and records what it said — never
    /// what it means.
    ///
    /// **The band deliberately stops short of the verdict Owen wants.**
    /// "Quota is inert on this seed" needs two facts: a tri-state that never
    /// leaves `.belowLimit`, AND the system emitting
    /// `Usage limit status tracker delegate is nil`. The app can see the
    /// first and cannot see the second, so the row records the first and
    /// carries the grep for the second. A row that concluded "inert" from its
    /// own half would be the #215 error in a new costume: a reading taken in
    /// a configuration that cannot produce the contrast, reported as the
    /// contrast.
    private func recordQuotaRow(repeats: Int) async {
        if let refusal = Self.privateCloudProbeRefusal {
            Self.batteryEmit("surface: [quota] NOT MEASURED — \(refusal)")
            Self.batteryRecorder.recordProbe(
                probe: "PrivateCloudComputeLanguageModel.quotaUsage",
                expected: true, correct: 0, trials: repeats,
                variant: "private-cloud", band: "quota", errors: repeats,
                metrics: ["scored": 0, "errors": Double(repeats)],
                notes: ["environment": Self.probeEnvironment, "notMeasured": refusal,
                        "correlateWith": Self.quotaTrackerLogNeedle])
            return
        }
        var statuses: [String] = []
        var approaching = 0
        var limitReached = 0
        var unknownStatus = 0
        var withSuggestion = 0
        var withResetDate = 0
        var lastResetDate: Date?
        for _ in 0 ..< repeats {
            let usage = PrivateCloudComputeLanguageModel().quotaUsage
            switch usage.status {
            case .belowLimit(let info):
                statuses.append(info.isApproachingLimit ? "belowLimit(approaching)" : "belowLimit")
                if info.isApproachingLimit { approaching += 1 }
            case .limitReached:
                statuses.append("limitReached")
                limitReached += 1
            @unknown default:
                // NOT a default that shrugs. `Status` is non-frozen, and this
                // item exists because this surface changes every beta — a
                // third case appearing is a FINDING, so it is recorded under
                // its own name instead of being folded into `belowLimit` by
                // an `else`. It counts as neither below nor reached.
                statuses.append("unknown")
                unknownStatus += 1
            }
            if usage.limitIncreaseSuggestion != nil { withSuggestion += 1 }
            if let reset = usage.resetDate { withResetDate += 1; lastResetDate = reset }
        }
        // `distinct` over repeats with no traffic between them is expected to
        // be 1 whether quota is live or inert, so it is recorded and NOT
        // interpreted. What it can still catch is the opposite of inertness —
        // a value that moves on its own.
        let distinct = Set(statuses).count
        var metrics: [String: Double] = [
            "scored": Double(statuses.count),
            "errors": 0,
            "distinct": Double(distinct),
            "isApproachingLimit": Double(approaching),
            "isLimitReached": Double(limitReached),
            "hasLimitIncreaseSuggestion": Double(withSuggestion),
            "hasResetDate": Double(withResetDate),
        ]
        metrics["unknownStatus"] = Double(unknownStatus)
        metrics["belowLimit"] = Double(repeats - limitReached - unknownStatus)
        var notes = ["environment": Self.probeEnvironment,
                     "statuses": statuses.joined(separator: "|"),
                     "correlateWith": Self.quotaTrackerLogNeedle]
        if let lastResetDate {
            notes["resetDate"] = ISO8601DateFormatter().string(from: lastResetDate)
        }
        Self.batteryEmit("surface: [quota] statuses=\(statuses.joined(separator: "|")) distinct=\(distinct) unknown=\(unknownStatus)/\(repeats) approaching=\(approaching)/\(repeats) limitReached=\(limitReached)/\(repeats) suggestion=\(withSuggestion)/\(repeats) resetDate=\(notes["resetDate"] ?? "—") correlateWith=\"\(Self.quotaTrackerLogNeedle)\"")
        Self.batteryRecorder.recordProbe(
            probe: "PrivateCloudComputeLanguageModel.quotaUsage",
            expected: true, correct: statuses.count, trials: repeats,
            variant: "private-cloud", band: "quota", errors: 0,
            metrics: metrics, notes: notes)
    }

    // MARK: - Band 3: frameworks (388-D, the device-answerable half)

    /// One row per framework: does it load in THIS process on THIS device.
    ///
    /// The handle is deliberately NOT closed. `dlclose` on a system framework
    /// is a no-op at best and a way to unload something another subsystem is
    /// mid-way through using at worst; leaking three handles for the lifetime
    /// of a debug launch costs nothing and cannot break anything.
    private func recordFrameworkRows(using loader: FrameworkLoader) {
        for entry in Self.probedFrameworkPaths {
            let result = loader(entry.path)
            let loaded = result.loaded
            var notes = ["environment": Self.probeEnvironment, "path": entry.path]
            if !loaded, let message = result.error {
                notes["dlerror"] = message
            }
            Self.batteryEmit("surface: [frameworks] \(entry.name) loaded=\(loaded) path=\(entry.path)\(notes["dlerror"].map { " dlerror=\($0)" } ?? "")")
            Self.batteryRecorder.recordProbe(
                probe: "dlopen \(entry.name)",
                expected: true, correct: loaded ? 1 : 0, trials: 1,
                variant: entry.name, band: "frameworks",
                // A framework that did not load MEASURED SUCCESSFULLY — the
                // answer is simply "no". `errors` stays 0 because nothing
                // prevented the reading, which is the distinction the rest of
                // this file spends its length on.
                errors: 0,
                metrics: ["loaded": loaded ? 1 : 0, "scored": 1, "errors": 0],
                notes: notes)
        }
    }
}
#endif

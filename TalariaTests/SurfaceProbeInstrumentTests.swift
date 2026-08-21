#if DEBUG
import Foundation
import Testing
@testable import Talaria

/// **#388's instrument, tested for the one property the evening depends on.**
///
/// The MEASUREMENT bars (388-A…D) cannot be met here and this file does not
/// pretend otherwise: the simulator has no entitlement, so both PCC rows are
/// NOT MEASURED by construction, and that is the whole point of 388-C. What is
/// pinned instead is that the instrument **reports its own blindness as
/// blindness** — because the failure this project has been bitten by is not a
/// probe that returns nothing, it is a probe that returns a confident zero.
///
/// `21F0C10D`, `#215`, and #388-C are three statements of the same rule. The
/// sim is used here as the unmeasurable environment on purpose: it is the only
/// place the not-measured path can be exercised at all.
struct SurfaceProbeRegistryTests {

    @Test func pccSurfaceIsRegisteredReadOnly() throws {
        let spec = try #require(InstrumentRegistry.spec(named: "pcc-surface"))
        #expect(spec.confirmationMode == .none)
        #expect(!spec.writesEventKit && !spec.writesAlarms)
        // No `ActionBatteryCell` dimension — #341's conductor must REFUSE a
        // `TALARIA_CELLS` request for this instrument rather than ignore one.
        #expect(spec.defaultCells == nil)
    }

    /// The four capability names are the instrument's vocabulary: they appear
    /// in the artifact, in the log line and in the assertions below. Pinned so
    /// a rename shows up as one red test rather than as an artifact whose
    /// columns quietly stopped matching last week's.
    @Test func theFourProbedCapabilitiesAreNamedAndDistinct() {
        let names = LocalChatBackend.probedCapabilities.map(\.name)
        #expect(names == ["vision", "toolCalling", "reasoning", "guidedGeneration"])
        #expect(Set(names).count == 4)
    }

    /// #388-D's device-answerable half asks about exactly three frameworks,
    /// by absolute path. A typo'd path is a row that reports `loaded=false`
    /// about a framework that is present — a false finding that looks like a
    /// real one.
    @Test func theThreeProbedFrameworksAreNamedWithSystemPaths() {
        let entries = LocalChatBackend.probedFrameworkPaths
        #expect(entries.map(\.name) == ["ImagePlayground", "VisualIntelligence", "MediaIntelligence"])
        for entry in entries {
            #expect(entry.path == "/System/Library/Frameworks/\(entry.name).framework/\(entry.name)",
                    "\(entry.name) has a path that does not match its own name: \(entry.path)")
        }
    }

    /// Bar 388-C's structural half. The environment string is what stops a
    /// sim reading being folded into a device finding three weeks from now,
    /// so it may only ever be one of two known values.
    @Test func theEnvironmentIsAlwaysLabelledAsOneOfTwoKnownValues() {
        #expect(["simulator", "device"].contains(LocalChatBackend.probeEnvironment))
        #if targetEnvironment(simulator)
        #expect(LocalChatBackend.probeEnvironment == "simulator")
        #else
        #expect(LocalChatBackend.probeEnvironment == "device")
        #endif
    }

    /// The refusal and the gate are the SAME fact, and a build where they
    /// disagree is a build where the artifact's `notMeasured` note contradicts
    /// the row beside it.
    /// `@MainActor` on the test, not the suite: the gate and the refusal are
    /// statics on a `@MainActor` type, and everything else in here is
    /// genuinely actor-free.
    @MainActor
    @Test func theRefusalIsPresentExactlyWhenTheGateIsClosed() {
        if LocalChatBackend.pccGrantConfirmed {
            #expect(LocalChatBackend.privateCloudProbeRefusal == nil)
        } else {
            let refusal = LocalChatBackend.privateCloudProbeRefusal
            #expect(refusal != nil)
            // The note has to name the CAUSE, not just assert a negative —
            // a bare "not measured" a year from now is indistinguishable
            // from an instrument that broke.
            #expect(refusal?.contains("pccGrantConfirmed=false") == true)
            #expect(refusal?.contains(LocalChatBackend.probeEnvironment) == true)
        }
    }
}

/// The run-level bars. `.serialized` for the same reason `PreflightInstrumentRunTests`
/// is: every test here drives the ONE shared static recorder through
/// `beginBatteryRun()`'s global mutex, and two in parallel would have the
/// second refused — the mutex working correctly and the test failing for a
/// reason unrelated to the instrument.
@Suite(.serialized)
@MainActor
struct SurfaceProbeRunTests {

    private func makeBackend() -> LocalChatBackend {
        LocalChatBackend(
            persistence: UserDefaultsAppPersistenceStore(
                defaults: UserDefaults(suiteName: "surface-probe-instrument-tests")!
            ),
            intelligence: LocalIntelligenceService()
        )
    }

    /// 🔴 **The suite never calls `dlopen`, and that is a requirement rather
    /// than a preference.**
    ///
    /// The first version of these tests let the framework band use the real
    /// loader, so seven runs pulled three system frameworks into the shared
    /// test-host process — permanently, for every test scheduled after them.
    /// The gate went red on a timing-sensitive test in ANOTHER file
    /// (`foregroundWritesWidgetSnapshot…`) while the same gate on clean
    /// `main` minutes earlier was green at 2392/14. **A probe that changes
    /// the process it is measured in is not a probe.**
    ///
    /// The fake also reaches what the real loader cannot: the NOT-LOADED
    /// branch, unreachable on a machine that has all three frameworks.
    private func fakeLoader(
        loaded: Bool, error: String? = nil
    ) -> LocalChatBackend.FrameworkLoader {
        { _ in (loaded, error) }
    }

    /// A SET DIFFERENCE, not `loadRuns().first` — the persisted `startedAt` is
    /// ISO8601 at second granularity and this instrument finishes in
    /// milliseconds, so two runs inside one second sort arbitrarily. #335 hit
    /// exactly this and the note it left is why this file did not.
    private func idsOnDisk() -> Set<UUID> {
        Set(LocalChatBackend.batteryRunStore.loadRuns().map(\.id))
    }

    private func freshRun(after known: Set<UUID>) throws -> BatteryRunRecord {
        try #require(LocalChatBackend.batteryRunStore.loadRuns().first { !known.contains($0.id) },
                     "no NEW run record appeared — exactly what #333's conductor reports as failed")
    }

    @Test func theProbeSealsARunWithAllThreeBands() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()

        await backend.runPCCSurfaceProbe(trials: 2, frameworkLoader: fakeLoader(loaded: true))

        let record = try freshRun(after: known)
        #expect(record.endedCleanly == true, "endRun() must run on the sim path too, or the artifact is INCOMPLETE")
        #expect(record.kind == "pcc-surface")
        #expect(Set(record.probes.compactMap(\.band)) == ["capabilities", "quota", "frameworks"])
    }

    /// **388-A's shape: the contrast needs BOTH rows.**
    ///
    /// The tempting implementation skips the PCC row where it cannot be read.
    /// That produces a band with one row, which cannot be compared against
    /// anything — and worse, it looks complete. So the row is written either
    /// way and says which of the two it is.
    @Test func bothTiersGetACapabilityRowEvenWhereOneCannotBeRead() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runPCCSurfaceProbe(trials: 1, frameworkLoader: fakeLoader(loaded: true))
        let record = try freshRun(after: known)

        let rows = record.probes.filter { $0.band == "capabilities" }
        #expect(Set(rows.compactMap(\.variant)) == ["on-device", "private-cloud"])
        for row in rows {
            #expect(row.trials == LocalChatBackend.probedCapabilities.count,
                    "a capability row's denominator is the number of capabilities PROBED")
            #expect(row.notes?["environment"] == LocalChatBackend.probeEnvironment)
        }
    }

    /// The on-device row is the band's control: it needs no entitlement, so a
    /// build where IT is unmeasured has a problem that has nothing to do with
    /// PCC. Its four flags are always present, whatever they say.
    @Test func theOnDeviceRowIsAlwaysMeasuredAndCarriesAllFourFlags() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runPCCSurfaceProbe(trials: 1, frameworkLoader: fakeLoader(loaded: true))
        let record = try freshRun(after: known)

        let row = try #require(record.probes.first { $0.band == "capabilities" && $0.variant == "on-device" })
        #expect(row.errors == 0)
        #expect(row.notes?["notMeasured"] == nil)
        for entry in LocalChatBackend.probedCapabilities {
            let flag = try #require(row.metrics?[entry.name],
                                    "the on-device row dropped \(entry.name) — a missing flag reads as an unasked question")
            #expect(flag == 0 || flag == 1)
        }
        // `correct` is capabilities PRESENT, and it must agree with the flags
        // rather than being counted a second way.
        let present = LocalChatBackend.probedCapabilities
            .compactMap { row.metrics?[$0.name] }.filter { $0 == 1 }.count
        #expect(row.correct == present)
        #expect(row.metrics?["capabilityCount"] == Double(present))
    }

    /// 🔴 **The bar this file exists for.**
    ///
    /// Where PCC cannot be read, the row must record NOT MEASURED — errors
    /// equal to what it tried to read, and **no per-capability metrics at
    /// all**. A `vision: 0` written here would be byte-identical to a device
    /// row where PCC genuinely lacks vision, and 388-A's entire finding is
    /// which of those two it is.
    @Test func anUnreadablePrivateCloudRowRecordsNotMeasuredAndNoZeroFlags() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runPCCSurfaceProbe(trials: 1, frameworkLoader: fakeLoader(loaded: true))
        let record = try freshRun(after: known)

        let row = try #require(record.probes.first { $0.band == "capabilities" && $0.variant == "private-cloud" })
        if LocalChatBackend.pccGrantConfirmed {
            // On a device the row is a real reading; the flags must be there.
            #expect(row.errors == 0)
            for entry in LocalChatBackend.probedCapabilities {
                #expect(row.metrics?[entry.name] != nil)
            }
        } else {
            #expect(row.errors == LocalChatBackend.probedCapabilities.count)
            #expect(row.correct == 0)
            #expect(row.notes?["notMeasured"] != nil)
            for entry in LocalChatBackend.probedCapabilities {
                #expect(row.metrics?[entry.name] == nil,
                        "\(entry.name) was written as a value on a row that measured NOTHING — a zero here is a false finding")
            }
        }
    }

    /// The quota row obeys the same rule, and carries the half the app cannot
    /// see: 388-B's verdict needs a system log line, so the row records the
    /// needle instead of concluding without it.
    @Test func theQuotaRowCarriesItsCorrelationNeedleWhetherOrNotItCouldRead() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runPCCSurfaceProbe(trials: 2, frameworkLoader: fakeLoader(loaded: true))
        let record = try freshRun(after: known)

        let row = try #require(record.probes.first { $0.band == "quota" })
        #expect(row.trials == 2)
        #expect(row.notes?["correlateWith"] == LocalChatBackend.quotaTrackerLogNeedle)
        #expect(row.notes?["environment"] == LocalChatBackend.probeEnvironment)
        if LocalChatBackend.pccGrantConfirmed {
            #expect(row.errors == 0)
            #expect(row.metrics?["distinct"] != nil)
            #expect(row.notes?["statuses"] != nil)
        } else {
            #expect(row.errors == 2, "an unreadable quota band must report every attempt as unread")
            #expect(row.metrics?["isApproachingLimit"] == nil,
                    "a quota flag on a row that never read quota is a fabricated reading")
            #expect(row.notes?["notMeasured"] != nil)
        }
    }

    /// 388-D's device-answerable half. **A framework that did not load is a
    /// successful measurement whose answer is "no"** — so unlike the PCC rows,
    /// `errors` stays 0 here and `loaded` carries the finding. Conflating the
    /// two would make an absent framework indistinguishable from an unasked
    /// question, which is the same mistake in the opposite direction.
    @Test func everyFrameworkRowReportsALoadResultRatherThanAnError() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runPCCSurfaceProbe(trials: 1, frameworkLoader: fakeLoader(loaded: true))
        let record = try freshRun(after: known)

        let rows = record.probes.filter { $0.band == "frameworks" }
        #expect(Set(rows.compactMap(\.variant)) == Set(LocalChatBackend.probedFrameworkPaths.map(\.name)))
        for row in rows {
            #expect(row.errors == 0, "a framework that did not load MEASURED — the answer is no, not unknown")
            #expect(row.metrics?["loaded"] == 1)
            #expect(row.correct == 1)
            #expect(row.notes?["path"] != nil)
        }
    }

    /// **The branch the real loader cannot reach.** Every framework in the
    /// list is present on this Mac and on the phone, so "did not load" is
    /// unobservable without the seam — and it is the branch whose scoring the
    /// band's whole design rests on: a framework that is ABSENT measured
    /// successfully, so `errors` stays 0 and `loaded` carries the answer.
    /// Scoring it as an error would make an absent framework
    /// indistinguishable from an unasked question.
    @Test func aFrameworkThatDidNotLoadIsAMeasurementNotAnError() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runPCCSurfaceProbe(
            trials: 1,
            frameworkLoader: fakeLoader(loaded: false, error: "image not found"))
        let record = try freshRun(after: known)

        let rows = record.probes.filter { $0.band == "frameworks" }
        #expect(rows.count == LocalChatBackend.probedFrameworkPaths.count)
        for row in rows {
            #expect(row.errors == 0, "absence is an ANSWER — scoring it as an error loses the finding")
            #expect(row.metrics?["loaded"] == 0)
            #expect(row.correct == 0)
            #expect(row.notes?["dlerror"] == "image not found",
                    "a row that reports NOT LOADED must carry the reason it was given")
        }
    }

    /// Every row, every band: the tally that stops fail-safe noise reading as
    /// data. `21F0C10D` cost a whole battery to this exact gap.
    @Test func everyRowCarriesAnErrorTallyAndAScoredCount() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runPCCSurfaceProbe(trials: 1, frameworkLoader: fakeLoader(loaded: true))
        let record = try freshRun(after: known)

        #expect(!record.probes.isEmpty)
        for row in record.probes {
            #expect(row.errors != nil, "row \"\(row.probe)\" has no error tally — unsampled reads as clean")
            #expect(row.metrics?["scored"] != nil, "row \"\(row.probe)\" has no scored count")
            #expect(row.notes?["environment"] != nil, "row \"\(row.probe)\" is unlabelled — bar 388-C")
        }
    }
}
#endif

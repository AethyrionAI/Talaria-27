#if DEBUG
import Foundation
import Testing
@testable import Talaria

/// #334: the read-only FM measurement instruments, tested STRUCTURALLY.
///
/// Structural is not a compromise here, it is the only honest option: the
/// simulator cannot generate at all (beta5 — an un-bridged
/// `LanguageModelError -1` wrapping `ModelManagerError 1026`, `contextSize`
/// reported as 0, and typed catches blind), so a test that required a real
/// measurement would be a test that could only ever pass on hardware. What
/// these pin instead is the property the unattended runner depends on: the
/// instrument opens a recorder run, records its rows — INCLUDING the rows
/// where the model threw — and closes the run, whatever the model does. **The
/// sim IS the throwing environment**, which is exactly why it is used as one.
struct PreflightInstrumentRegistryTests {

    @Test func tokenCountPreflightIsRegisteredReadOnly() throws {
        let spec = try #require(InstrumentRegistry.spec(named: "tokencount-preflight"))
        #expect(spec.confirmationMode == .none)
        #expect(!spec.writesEventKit && !spec.writesAlarms)
    }

    @Test func fmAsymmetriesIsRegisteredReadOnly() throws {
        let spec = try #require(InstrumentRegistry.spec(named: "fm-asymmetries"))
        #expect(spec.confirmationMode == .none)
        #expect(!spec.writesEventKit && !spec.writesAlarms)
    }
}

/// The record change #334 needed: two optional dictionaries on
/// `RouterProbeRecord`. Additive-optional is a claim about DECODING as much
/// as encoding — the store holds runs going back to #196 — so both directions
/// are pinned here.
struct PreflightRecordShapeTests {

    @Test func metricsAndNotesRoundTripThroughTheStoreEncoding() throws {
        let row = RouterProbeRecord(
            probe: "schema", expected: true, correct: 3, trials: 3,
            variant: "two-field", band: "response-cap", errors: 0,
            metrics: ["value": 21, "cap": 128, "headroom": 107],
            notes: ["json": #"{"needsDeviceTool":false}"#])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RouterProbeRecord.self, from: encoder.encode(row))
        #expect(decoded == row)
        #expect(decoded.metrics?["headroom"] == 107)
    }

    /// A pre-#334 row carries neither field, and must still decode — with
    /// **nil, meaning NOT MEASURED**, never a zero that would read as a
    /// measurement of nothing (#213's distinction, applied to the new fields).
    @Test func legacyRowsWithoutMetricsStillDecode() throws {
        let legacy = #"{"probe":"What's 2+2?","expected":false,"correct":10,"trials":10}"#
        let decoder = JSONDecoder()
        let row = try decoder.decode(RouterProbeRecord.self, from: Data(legacy.utf8))
        #expect(row.metrics == nil)
        #expect(row.notes == nil)
        #expect(row.correct == 10)
    }
}

/// The run-level structural bar, and the one the #333 conductor's verdict
/// rests on: **a new `BatteryRunRecord` must exist and be sealed**, or the
/// unattended harness reads `failed` however good the measurement was.
///
/// `.serialized` because every test in here drives the ONE shared static
/// recorder + run store through `beginBatteryRun()`'s global mutex — two of
/// them in parallel would have the second refused, which is the mutex working
/// correctly and the test failing for a reason that has nothing to do with
/// the instrument.
@Suite(.serialized)
@MainActor
struct PreflightInstrumentRunTests {

    private func makeBackend() -> LocalChatBackend {
        LocalChatBackend(
            persistence: UserDefaultsAppPersistenceStore(
                defaults: UserDefaults(suiteName: "preflight-instrument-tests")!
            ),
            intelligence: LocalIntelligenceService()
        )
    }

    /// The ids already on disk, and then the ONE that was not there before.
    ///
    /// **Not `loadRuns().first`, and the difference is a real trap rather than
    /// a style preference.** The store sorts newest-first by `startedAt`, but
    /// the persisted form is ISO8601 — SECOND granularity — so two runs inside
    /// the same second decode to equal keys and the sort gives no order
    /// between them. These instruments finish in a second or two, which is
    /// precisely the regime where that bites: an earlier test's record came
    /// back as "newest" and three assertions failed for a reason that had
    /// nothing to do with the instrument. A set difference names MY run
    /// whatever the clock did. (#333's conductor reads `first` — see the watch
    /// note in OPEN_ITEMS #334; harmless there because separate launches are
    /// never a second apart, and named rather than left to be rediscovered.)
    private func idsOnDisk() -> Set<UUID> {
        Set(LocalChatBackend.batteryRunStore.loadRuns().map(\.id))
    }

    private func freshRun(after known: Set<UUID>) throws -> BatteryRunRecord {
        try #require(LocalChatBackend.batteryRunStore.loadRuns().first { !known.contains($0.id) },
                     "no NEW run record appeared — exactly what #333's conductor reports as failed")
    }

    @Test func tokenCountPreflightSealsARunEvenWhereTheModelThrows() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()

        await backend.runTokenCountPreflight(trials: 2)

        let record = try freshRun(after: known)
        #expect(record.endedCleanly == true, "endRun() must run on the sim path too, or the artifact is INCOMPLETE")
        #expect(record.kind == "tokencount-preflight")
        #expect(!record.probes.isEmpty, "an empty run is DROPPED by endRun() and the conductor then reports failed")
    }

    /// `21F0C10D`'s rule made structural: every row that could throw carries
    /// an error tally, so a band that measured nothing cannot read as a band
    /// that measured zero. On the sim most rows ARE error rows — that is the
    /// point of running this here.
    @Test func everyPreflightRowCarriesItsErrorTallyAndScoredCount() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runTokenCountPreflight(trials: 2)
        let record = try freshRun(after: known)

        for row in record.probes {
            #expect(row.errors != nil, "row \"\(row.probe)\" has no error tally — unsampled reads as clean")
            #expect(row.metrics?["scored"] != nil, "row \"\(row.probe)\" has no scored count")
            #expect(row.trials == 2)
        }
    }

    @Test func fmAsymmetriesSealsARunWithAllThreeBands() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()

        await backend.runFMAsymmetriesProbe(trials: 1)

        let record = try freshRun(after: known)
        #expect(record.endedCleanly == true)
        #expect(record.kind == "fm-asymmetries")
        // #324-W3 names three questions; three bands answer them, and a band
        // that silently stopped being recorded is the failure this pins.
        let bands = Set(record.probes.compactMap(\.band))
        #expect(bands == ["boundary", "variant", "response-cap-behavior"])
    }

    /// The boundary band's whole point is the COMPARISON, so both sides and
    /// both ratios have to survive into the record — a run that reports one
    /// count answers nothing.
    @Test func boundaryBandRecordsBothSizesAndTheCharacterRatio() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runFMAsymmetriesProbe(trials: 1)
        let record = try freshRun(after: known)

        let low = try #require(record.probes.first { $0.band == "boundary" && $0.variant == "4096" })
        let high = try #require(record.probes.first { $0.band == "boundary" && $0.variant == "8192" })
        #expect(low.metrics?["targetTokens"] == 4096)
        #expect(high.metrics?["targetTokens"] == 8192)
        #expect(high.metrics?["chars"] ?? 0 > (low.metrics?["chars"] ?? 0))
        // Known even where the tokenizer refuses — characters are countable
        // without a model, so this ratio is never the missing half.
        #expect(high.metrics?["charRatioVs4096"] != nil)
    }

    /// "none" is a real outcome and must be sayable: a band where every trial
    /// timed out has measured nothing, and a classifier that could only emit
    /// "threw"/"truncated" would launder that into a finding.
    @Test func responseCapBandClassifiesItsBehaviourWithEvidence() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runFMAsymmetriesProbe(trials: 1)
        let record = try freshRun(after: known)

        let row = try #require(record.probes.first { $0.band == "response-cap-behavior" })
        let behavior = try #require(row.notes?["behavior"])
        #expect(["threw", "truncated", "mixed", "none"].contains(behavior))
        #expect(row.metrics?["cap"].map(Int.init) == LocalChatBackend.responseCapProbeCap)
        #expect(row.errors != nil)
        // On the sim the generation throws, so the evidence must be the error
        // text — the row cannot claim a behaviour it did not observe.
        if behavior == "threw" { #expect(row.notes?["firstError"] != nil) }
    }

    /// The caps are READ from the production constants, not retyped into the
    /// instrument — the failure this guards is a hardcoded 128 still
    /// reporting comfortable headroom the day someone changes
    /// `twoFieldRouterOptions`.
    @Test func responseCapRowsCarryTheProductionCaps() async throws {
        let backend = makeBackend()
        let known = idsOnDisk()
        await backend.runTokenCountPreflight(trials: 1)
        let record = try freshRun(after: known)

        let twoField = try #require(record.probes.first {
            $0.band == "response-cap" && $0.variant == "two-field"
        })
        let oneField = try #require(record.probes.first {
            $0.band == "response-cap" && $0.variant == "one-field"
        })
        #expect(twoField.metrics?["cap"].map(Int.init)
                == LocalChatBackend.twoFieldRouterOptions.maximumResponseTokens)
        #expect(oneField.metrics?["cap"].map(Int.init)
                == LocalChatBackend.toolIntentRouterOptions.maximumResponseTokens)
    }
}
#endif

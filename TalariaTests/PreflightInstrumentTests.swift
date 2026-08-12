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

    @Test func tokenCountPreflightSealsARunEvenWhereTheModelThrows() async throws {
        let backend = makeBackend()
        let before = LocalChatBackend.batteryRunStore.loadRuns().first?.id

        await backend.runTokenCountPreflight(trials: 2)

        let record = try #require(LocalChatBackend.batteryRunStore.loadRuns().first)
        #expect(record.id != before, "the instrument must open a NEW run — a conductor reads exactly this")
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
        await backend.runTokenCountPreflight(trials: 2)
        let record = try #require(LocalChatBackend.batteryRunStore.loadRuns().first)

        for row in record.probes {
            #expect(row.errors != nil, "row \"\(row.probe)\" has no error tally — unsampled reads as clean")
            #expect(row.metrics?["scored"] != nil, "row \"\(row.probe)\" has no scored count")
            #expect(row.trials == 2)
        }
    }

    /// The caps are READ from the production constants, not retyped into the
    /// instrument — the failure this guards is a hardcoded 128 still
    /// reporting comfortable headroom the day someone changes
    /// `twoFieldRouterOptions`.
    @Test func responseCapRowsCarryTheProductionCaps() async throws {
        let backend = makeBackend()
        await backend.runTokenCountPreflight(trials: 1)
        let record = try #require(LocalChatBackend.batteryRunStore.loadRuns().first)

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

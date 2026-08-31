import Testing
@testable import Talaria

/// **#417-F — the location answer can never be a bare label.**
///
/// #417's device instrument proved the one fabricating condition is a tool
/// result with no data AND no failure string, and the 2026-08-30 audit found
/// exactly one production path that produces it: `"Current location: "` when
/// MapKit returns an all-nil map item (`reverseGeocodedParts` hands back a
/// non-nil EMPTY array, which the old nil-only guard passed through). These
/// pins route the empty case into the same honest failure string the
/// geocode-nil arm has always used — the shape #417 measured as protective
/// (0/40 fabrication) — and pin the populated composition unchanged.
@Suite("Location answer composition (#417-F)")
struct LocationAnswerCompositionTests {

    @Test("empty parts return the honest failure string, never the bare label")
    func emptyPartsReturnTheHonestFailureString() {
        let answer = LocationTool.locationAnswer(parts: [], horizontalAccuracyMeters: 12)
        #expect(answer.contains("reverse geocoding failed"))
        #expect(answer.contains("±12m"))
        #expect(!answer.contains("Current location:"))
    }

    @Test("all-empty-string parts are the empty case, not a bare label")
    func allEmptyStringPartsAreTheEmptyCase() {
        let answer = LocationTool.locationAnswer(parts: ["", ""], horizontalAccuracyMeters: 40)
        #expect(answer.contains("reverse geocoding failed"))
        #expect(answer.contains("±40m"))
        #expect(!answer.contains("Current location:"))
    }

    @Test("a populated result composes exactly as before")
    func populatedPartsComposeExactlyAsBefore() {
        let answer = LocationTool.locationAnswer(
            parts: ["Apple Park", "Cupertino", "CA"], horizontalAccuracyMeters: 5)
        #expect(answer == "Current location: Apple Park, Cupertino, CA")
    }

    @Test("duplicate parts stay deduplicated — the pre-fix behaviour, pinned")
    func duplicatesAreDeduplicated() {
        let answer = LocationTool.locationAnswer(
            parts: ["Cupertino", "Cupertino", "CA"], horizontalAccuracyMeters: 5)
        #expect(answer == "Current location: Cupertino, CA")
    }

    @Test("an empty fragment among real parts is dropped, not rendered as a stray comma")
    func emptyFragmentAmongRealPartsIsDropped() {
        let answer = LocationTool.locationAnswer(
            parts: ["", "Cupertino"], horizontalAccuracyMeters: 5)
        #expect(answer == "Current location: Cupertino")
    }
}

import Foundation
import Testing
@testable import Talaria

/// #156b D6 — tolerant decoding of `GET /v1/skills` records and the
/// row-level display computeds. Upstream is not contractual: every field
/// optional, unknown fields ignored, a record without a usable name dropped
/// at the list level rather than failing the fetch.
struct SkillDecodingTests {

    private func decodeList(_ json: String) throws -> SkillListResponse {
        try JSONDecoder().decode(SkillListResponse.self, from: Data(json.utf8))
    }

    // MARK: - Record decoding

    @Test func fullRecordDecodes() throws {
        let skill = try JSONDecoder().decode(Skill.self, from: Data("""
        {"name": "deep-research", "description": "Fan-out research harness.", "category": "research"}
        """.utf8))
        #expect(skill.name == "deep-research")
        #expect(skill.description == "Fan-out research harness.")
        #expect(skill.category == "research")
        #expect(skill.id == "deep-research")
    }

    @Test func nullCategoryDecodes() throws {
        let skill = try JSONDecoder().decode(Skill.self, from: Data("""
        {"name": "loose-skill", "description": "No bucket.", "category": null}
        """.utf8))
        #expect(skill.category == nil)
        #expect(skill.displayCategory == "Uncategorized")
    }

    @Test func missingDescriptionDecodes() throws {
        let skill = try JSONDecoder().decode(Skill.self, from: Data("""
        {"name": "terse"}
        """.utf8))
        #expect(skill.description == nil)
        #expect(skill.rowDescription == nil)
    }

    @Test func unknownFieldsAreIgnored() throws {
        let skill = try JSONDecoder().decode(Skill.self, from: Data("""
        {"name": "future", "description": "d", "category": "c",
         "enabled": true, "version": 3, "metadata": {"a": 1}}
        """.utf8))
        #expect(skill.name == "future")
    }

    @Test func wrongTypedFieldsDegradeToNil() throws {
        let skill = try JSONDecoder().decode(Skill.self, from: Data("""
        {"name": "odd", "description": 42, "category": ["a", "b"]}
        """.utf8))
        #expect(skill.description == nil)
        #expect(skill.category == nil)
        #expect(skill.displayCategory == "Uncategorized")
    }

    @Test func missingNameThrows() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Skill.self, from: Data("""
            {"description": "who am I", "category": "lost"}
            """.utf8))
        }
    }

    @Test func blankNameThrows() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Skill.self, from: Data("""
            {"name": "   ", "description": "blank"}
            """.utf8))
        }
    }

    // MARK: - List envelope

    @Test func listDecodesAndIgnoresEnvelopeExtras() throws {
        let response = try decodeList("""
        {"object": "list", "data": [
            {"name": "alpha", "category": "a"},
            {"name": "beta", "category": null}
        ], "total": 2}
        """)
        #expect(response.skills.map(\.name) == ["alpha", "beta"])
        #expect(response.skippedRowCount == 0)
    }

    @Test func recordWithoutNameIsDroppedNotFatal() throws {
        let response = try decodeList("""
        {"object": "list", "data": [
            {"name": "kept-one"},
            {"description": "nameless"},
            {"name": ""},
            {"name": "kept-two"},
            "not-even-an-object"
        ]}
        """)
        #expect(response.skills.map(\.name) == ["kept-one", "kept-two"])
        #expect(response.skippedRowCount == 3)
    }

    @Test func emptyListDecodes() throws {
        let response = try decodeList("""
        {"object": "list", "data": []}
        """)
        #expect(response.skills.isEmpty)
        #expect(response.skippedRowCount == 0)
    }

    // MARK: - displayCategory

    @Test func whitespaceCategoryIsUncategorized() throws {
        let skill = try JSONDecoder().decode(Skill.self, from: Data("""
        {"name": "spacey", "category": "  "}
        """.utf8))
        #expect(skill.displayCategory == "Uncategorized")
    }

    @Test func categoryTrimsForDisplay() {
        let skill = Skill(name: "s", description: nil, category: " research ")
        #expect(skill.displayCategory == "research")
    }

    // MARK: - rowDescription (verified: live descriptions embed newlines)

    @Test func rowDescriptionCollapsesNewlines() {
        let skill = Skill(
            name: "multi",
            description: "First line.\nSecond line.\r\n\nThird line.",
            category: nil
        )
        #expect(skill.rowDescription == "First line. Second line. Third line.")
    }

    @Test func rowDescriptionTrimsEdges() {
        let skill = Skill(name: "pad", description: "  padded  \n tail ", category: nil)
        #expect(skill.rowDescription == "padded tail")
    }

    @Test func newlineOnlyDescriptionReadsAsAbsent() {
        let skill = Skill(name: "empty", description: "\n\n  \n", category: nil)
        #expect(skill.rowDescription == nil)
    }

    // MARK: - Search matching

    @Test func matchesIsCaseInsensitiveAcrossFields() {
        let skill = Skill(name: "deep-research", description: "Fan-out HARNESS", category: "Research")
        #expect(skill.matches("DEEP"))
        #expect(skill.matches("harness"))
        #expect(skill.matches("research"))
        #expect(!skill.matches("kubernetes"))
    }

    @Test func blankQueryMatchesEverything() {
        let skill = Skill(name: "anything", description: nil, category: nil)
        #expect(skill.matches(""))
        #expect(skill.matches("   "))
    }

    @Test func nilFieldsDoNotMatchButDoNotCrash() {
        let skill = Skill(name: "bare", description: nil, category: nil)
        #expect(skill.matches("bare"))
        #expect(!skill.matches("missing"))
    }
}

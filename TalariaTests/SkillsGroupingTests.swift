import Foundation
import Testing
@testable import Talaria

/// #156b D6 — the browser's presentation math: category grouping with
/// Uncategorized last, case-insensitive ordering, and search filtering
/// (including the empty result that triggers the no-matches state).
struct SkillsGroupingTests {

    private func skill(_ name: String, category: String? = nil, description: String? = nil) -> Skill {
        Skill(name: name, description: description, category: category)
    }

    @Test func groupsSortCaseInsensitivelyWithUncategorizedLast() {
        let groups = SkillsPresentation.groups(from: [
            skill("one", category: "zeta"),
            skill("two", category: nil),
            skill("three", category: "Alpha"),
            skill("four", category: "beta"),
            skill("five", category: ""),
        ])
        #expect(groups.map(\.title) == ["Alpha", "beta", "zeta", "Uncategorized"])
    }

    @Test func uncategorizedBucketsNilAndBlankTogether() {
        let groups = SkillsPresentation.groups(from: [
            skill("nil-cat", category: nil),
            skill("blank-cat", category: ""),
            skill("space-cat", category: "   "),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].title == "Uncategorized")
        #expect(groups[0].skills.count == 3)
    }

    @Test func skillsSortAlphabeticallyCaseInsensitivelyWithinGroup() {
        let groups = SkillsPresentation.groups(from: [
            skill("zulu", category: "c"),
            skill("Alpha", category: "c"),
            skill("mike", category: "c"),
        ])
        #expect(groups[0].skills.map(\.name) == ["Alpha", "mike", "zulu"])
    }

    @Test func clientSortsEvenWhenServerDidNot() {
        // Server pre-sorts via _sort_skills, but that is not relied on —
        // scrambled input must come out ordered.
        let groups = SkillsPresentation.groups(from: [
            skill("c-skill", category: "B"),
            skill("a-skill", category: "A"),
            skill("b-skill", category: "A"),
        ])
        #expect(groups.map(\.title) == ["A", "B"])
        #expect(groups[0].skills.map(\.name) == ["a-skill", "b-skill"])
    }

    // MARK: - Search

    @Test func queryFiltersAcrossGroups() {
        let groups = SkillsPresentation.groups(from: [
            skill("pdf-tools", category: "documents", description: "Read PDFs"),
            skill("web-search", category: "research", description: "Search the web"),
            skill("xlsx", category: "documents", description: "Spreadsheets"),
        ], matching: "search")
        #expect(groups.count == 1)
        #expect(groups[0].title == "research")
        #expect(groups[0].skills.map(\.name) == ["web-search"])
    }

    @Test func queryMatchingCategoryKeepsWholeBucket() {
        let groups = SkillsPresentation.groups(from: [
            skill("a", category: "Documents"),
            skill("b", category: "Documents"),
            skill("c", category: "research"),
        ], matching: "documents")
        #expect(groups.map(\.title) == ["Documents"])
        #expect(groups[0].skills.count == 2)
    }

    /// The no-matches state's trigger: matches exist ↔ groups exist.
    @Test func noMatchesYieldsEmptyGroups() {
        let groups = SkillsPresentation.groups(from: [
            skill("alpha", category: "a", description: "first"),
            skill("beta", category: "b", description: "second"),
        ], matching: "zzz-no-such-skill")
        #expect(groups.isEmpty)
    }

    @Test func blankQueryReturnsEverything() {
        let skills = [skill("a", category: "one"), skill("b")]
        #expect(SkillsPresentation.groups(from: skills, matching: "  ").flatMap(\.skills).count == 2)
    }

    @Test func emptyInputYieldsEmptyGroups() {
        #expect(SkillsPresentation.groups(from: []).isEmpty)
    }
}

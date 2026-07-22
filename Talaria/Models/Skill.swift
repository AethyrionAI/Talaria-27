import Foundation

/// #156b — one installed skill from the gateway's `GET /v1/skills` (verified
/// hermes-agent 0.19.0). The handler filters to enabled skills, so this list
/// IS what the agent can use — there is no enabled flag and no toggle surface.
///
/// Tolerant by construction (same posture as `CronJob`): the wire fields are
/// exactly `{name, description, category}` today, but upstream is not
/// contractual — every field is optional-decoded, unknown fields are ignored,
/// and a wrong-typed field degrades to nil. The one hard requirement is a
/// non-blank `name` (it is the identity and the value the cron `skills` field
/// carries); a record without one is skipped at the list level, never a
/// decode failure for the whole fetch.
struct Skill: Identifiable, Equatable {
    let name: String
    var description: String?
    var category: String?

    var id: String { name }
}

extension Skill {
    /// Grouping bucket: a nil/blank category is a real path (10 of 98 on the
    /// live host) — those group under "Uncategorized", sorted last.
    var displayCategory: String {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? SkillsPresentation.uncategorizedTitle : trimmed
    }

    /// Descriptions carry embedded newlines and run long (verified) — list
    /// rows render this single-line collapse; the expanded row shows the
    /// original text untouched.
    var rowDescription: String? {
        guard let description else { return nil }
        let collapsed = description
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    /// Case-insensitive match over name + description + category. A blank
    /// query matches everything (the unfiltered list).
    func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return [name, description, category]
            .compactMap { $0 }
            .contains { $0.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

// MARK: - Grouping

struct SkillGroup: Equatable {
    let title: String
    let skills: [Skill]
}

/// Pure presentation math for the browser (D3) so it is testable without a
/// view: filter by query, bucket by `displayCategory`, headers sorted
/// case-insensitively with Uncategorized LAST, skills alphabetical within.
/// Sorting is client-side by design — the server pre-sorts, but that is not
/// relied on.
enum SkillsPresentation {
    static let uncategorizedTitle = "Uncategorized"

    static func groups(from skills: [Skill], matching query: String = "") -> [SkillGroup] {
        let matched = skills.filter { $0.matches(query) }
        let buckets = Dictionary(grouping: matched) { $0.displayCategory }
        return buckets
            .sorted { lhs, rhs in
                let lhsLast = lhs.key == uncategorizedTitle
                let rhsLast = rhs.key == uncategorizedTitle
                if lhsLast != rhsLast { return rhsLast }
                let ordering = lhs.key.caseInsensitiveCompare(rhs.key)
                if ordering != .orderedSame { return ordering == .orderedAscending }
                return lhs.key < rhs.key
            }
            .map { title, unsorted in
                SkillGroup(title: title, skills: unsorted.sorted { lhs, rhs in
                    let ordering = lhs.name.caseInsensitiveCompare(rhs.name)
                    if ordering != .orderedSame { return ordering == .orderedAscending }
                    return lhs.name < rhs.name
                })
            }
    }
}

// MARK: - Tolerant decoding

extension Skill: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name, description, category
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let name = try? container.decode(String.self, forKey: .name),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.keyNotFound(
                CodingKeys.name,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Skill record has no usable name"
                )
            )
        }
        self.name = name
        description = try? container.decode(String.self, forKey: .description)
        category = try? container.decode(String.self, forKey: .category)
    }
}

// MARK: - Wire envelope

/// `GET /v1/skills` → `{"object": "list", "data": [...]}`, decoded
/// row-by-row so one malformed record skips that row instead of failing the
/// whole fetch — same posture as `CronJobListResponse`.
struct SkillListResponse: Decodable {
    let skills: [Skill]
    let skippedRowCount: Int

    private enum CodingKeys: String, CodingKey {
        case data
    }

    /// Never-throwing probe used to advance the unkeyed container past a bad
    /// row, whatever its JSON shape.
    private struct SkippedRow: Decodable {
        init() {}
        init(from decoder: any Decoder) {}
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var rows = try container.nestedUnkeyedContainer(forKey: .data)
        var decoded: [Skill] = []
        var skipped = 0
        while !rows.isAtEnd {
            let indexBeforeRow = rows.currentIndex
            do {
                decoded.append(try rows.decode(Skill.self))
            } catch {
                skipped += 1
                _ = try? rows.decode(SkippedRow.self)
                if rows.currentIndex == indexBeforeRow { break }
            }
        }
        skills = decoded
        skippedRowCount = skipped
    }
}

import Foundation

/// #156d — one session row from `GET /api/sessions` as the Insights lane
/// reads it: identity + labels + the cumulative usage block. This is a
/// BILLING/activity surface (#25 settled law): session `input_tokens` grows
/// superlinearly because every API call re-sends the whole history, so
/// nothing here may ever be presented as context occupancy or divided by a
/// context window. The CTX gauge (`SessionUsageIndexStore`) is a separate,
/// already-correct surface.
///
/// Tolerant by construction (same posture as `Skill`/`CronJob`): the one
/// hard requirement is a non-blank `id`; every other field optional-decodes
/// and a wrong-typed value degrades to nil, never a throw. Usage keys are
/// flat siblings of the row keys, so the row hands its own decoder to
/// `SessionUsage.decodeIfPresent` — the ONE decoder for those nine fields
/// (`SessionsHermesClient` reads it the same way; no second decoder).
struct SessionStatsRow: Identifiable, Equatable, Sendable {
    let id: String
    var title: String?
    var model: String?
    var source: String?
    var startedAt: Date?
    var endedAt: Date?
    var lastActive: Date?
    var messageCount: Int?
    /// Nil when NO usage key was present on the row — the honest-absence
    /// rule: such a session still counts as a session, but renders no
    /// numbers and contributes nothing to token math.
    var usage: SessionUsage?
}

extension SessionStatsRow {
    /// Wall-clock span of the session; nil unless both ends are known and
    /// ordered (a still-open or clock-skewed session shows nothing).
    var duration: TimeInterval? {
        guard let startedAt, let endedAt else { return nil }
        let span = endedAt.timeIntervalSince(startedAt)
        return span > 0 ? span : nil
    }

    /// Best-known recency for the list's relative timestamp: `last_active`
    /// when the wire carries it, else the session's end, else its start.
    var recency: Date? {
        lastActive ?? endedAt ?? startedAt
    }

    /// Row heading: a non-blank title, else the id prefix (ids are long
    /// opaque strings; eight characters identify without wrapping).
    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? String(id.prefix(8)) : trimmed
    }
}

extension SessionStatsRow: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, title, model, source
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case lastActive = "last_active"
        case messageCount = "message_count"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = try? container.decode(String.self, forKey: .id),
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Session row has no usable id"
                )
            )
        }
        self.id = id
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil
        model = (try? container.decodeIfPresent(String.self, forKey: .model)) ?? nil
        source = (try? container.decodeIfPresent(String.self, forKey: .source)) ?? nil
        startedAt = Self.epochDate(container, .startedAt)
        endedAt = Self.epochDate(container, .endedAt)
        lastActive = Self.epochDate(container, .lastActive)
        messageCount = (try? container.decodeIfPresent(Int.self, forKey: .messageCount)) ?? nil
        usage = SessionUsage.decodeIfPresent(from: decoder)
    }

    /// Timestamps ride as epoch seconds (same as the drawer's `last_active`
    /// read); absent, null, or wrong-typed → nil.
    private static func epochDate(
        _ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys
    ) -> Date? {
        guard let epoch = (try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil else {
            return nil
        }
        return Date(timeIntervalSince1970: epoch)
    }
}

// MARK: - Wire envelope

/// One page of `GET /api/sessions` → `{object, data, limit, offset,
/// has_more}`. Rows decode one-by-one so a malformed record skips that row
/// instead of failing the fetch (the `SkillListResponse` posture). A missing
/// or malformed `has_more` reads as false — the fetch stops rather than
/// looping on a shape it doesn't understand.
struct SessionStatsPage: Decodable {
    let rows: [SessionStatsRow]
    let hasMore: Bool
    let skippedRowCount: Int

    private enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
    }

    /// Never-throwing probe used to advance the unkeyed container past a bad
    /// row, whatever its JSON shape.
    private struct SkippedRow: Decodable {
        init() {}
        init(from decoder: any Decoder) {}
    }

    init(rows: [SessionStatsRow], hasMore: Bool, skippedRowCount: Int = 0) {
        self.rows = rows
        self.hasMore = hasMore
        self.skippedRowCount = skippedRowCount
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var rowContainer = try container.nestedUnkeyedContainer(forKey: .data)
        var decoded: [SessionStatsRow] = []
        var skipped = 0
        while !rowContainer.isAtEnd {
            let indexBeforeRow = rowContainer.currentIndex
            do {
                decoded.append(try rowContainer.decode(SessionStatsRow.self))
            } catch {
                skipped += 1
                _ = try? rowContainer.decode(SkippedRow.self)
                if rowContainer.currentIndex == indexBeforeRow { break }
            }
        }
        rows = decoded
        skippedRowCount = skipped
        hasMore = ((try? container.decodeIfPresent(Bool.self, forKey: .hasMore)) ?? nil) ?? false
    }
}

/// What the paged fetch hands the store: the assembled window plus whether
/// the page cap cut it short (→ the "showing the N most recent sessions"
/// banner — the scope of every number stays on screen, never implied).
struct SessionStatsFetch: Equatable, Sendable {
    var rows: [SessionStatsRow]
    var isTruncated: Bool
}

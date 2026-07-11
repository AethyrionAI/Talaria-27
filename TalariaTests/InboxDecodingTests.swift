import Foundation
import Testing
@testable import Talaria

/// #58 — one malformed inbox row must not poison the whole fetch. Before the
/// per-row decode, a single unknown `kind` (or bad UUID / date / missing
/// field) failed the entire `[RelayInboxItem]` array, which InboxStore
/// rendered as the relay-offline state. These tests feed the decoder mixed
/// good/bad payloads and assert the good rows survive, in order, with the
/// bad ones counted as skipped.
struct InboxDecodingTests {

    // MARK: - Payload builders

    private func goodRow(
        id: String,
        kind: String = "notification",
        title: String = "Title",
        priority: String = "normal",
        status: String = "pending",
        createdAt: String = "2026-07-10T12:00:00Z"
    ) -> String {
        """
        {
            "id": "\(id)",
            "kind": "\(kind)",
            "title": "\(title)",
            "body": "Body",
            "priority": "\(priority)",
            "status": "\(status)",
            "createdAt": "\(createdAt)"
        }
        """
    }

    private func payload(rows: [String]) -> Data {
        Data("{ \"items\": [\(rows.joined(separator: ","))] }".utf8)
    }

    /// Same decoder configuration the live relay path uses (custom relay
    /// date strategy) — the decoder under test must match production.
    private func decode(_ data: Data) throws -> LiveInboxService.InboxResponse {
        try RelayCoders.makeDecoder().decode(LiveInboxService.InboxResponse.self, from: data)
    }

    private let idA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    private let idB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    private let idC = "cccccccc-cccc-cccc-cccc-cccccccccccc"

    // MARK: - Clean payloads stay intact

    @Test func allGoodRowsDecodeInOrder() throws {
        let response = try decode(payload(rows: [
            goodRow(id: idA, kind: "alert"),
            goodRow(id: idB, kind: "approval"),
            goodRow(id: idC, kind: "reminder"),
        ]))

        #expect(response.skippedRows.isEmpty)
        #expect(response.items.map { $0.id.uuidString.lowercased() } == [idA, idB, idC])
    }

    @Test func everyValidKindDecodes() throws {
        let kinds = ["alert", "approval", "notification", "reminder", "suggestion"]
        let rows = kinds.enumerated().map { index, kind in
            goodRow(id: "0000000\(index)-0000-0000-0000-000000000000", kind: kind)
        }

        let response = try decode(payload(rows: rows))

        #expect(response.skippedRows.isEmpty)
        #expect(response.items.map(\.kind) == [.alert, .approval, .notification, .reminder, .suggestion])
    }

    @Test func emptyInboxDecodes() throws {
        let response = try decode(payload(rows: []))

        #expect(response.items.isEmpty)
        #expect(response.skippedRows.isEmpty)
    }

    // MARK: - Bad rows are skipped, good neighbors survive

    @Test func unknownKindRowIsSkippedNotFatal() throws {
        let response = try decode(payload(rows: [
            goodRow(id: idA),
            goodRow(id: idB, kind: "directive"),
            goodRow(id: idC),
        ]))

        #expect(response.skippedRows.count == 1)
        #expect(response.items.map { $0.id.uuidString.lowercased() } == [idA, idC])
    }

    @Test func skippedRowIsNamedForTheLog() throws {
        // gh#58's ask: the log line must name the poison row (id + raw kind)
        // so it can be found in the relay DB — the incident cost hours
        // because the bad row was anonymous.
        let response = try decode(payload(rows: [
            goodRow(id: idA),
            goodRow(id: idB, kind: "note"),
        ]))

        let skipped = try #require(response.skippedRows.first)
        #expect(skipped.id == idB)
        #expect(skipped.kind == "note")
    }

    @Test func bizarreSkippedRowStaysAnonymousWithoutDerailing() throws {
        // A non-object row can't yield an id/kind — the probe must still
        // advance and report an unidentified skip, never throw or loop.
        let response = try decode(payload(rows: [
            "\"just a string\"",
            goodRow(id: idA),
        ]))

        let skipped = try #require(response.skippedRows.first)
        #expect(skipped.id == nil)
        #expect(skipped.kind == nil)
        #expect(response.items.map { $0.id.uuidString.lowercased() } == [idA])
    }

    @Test func malformedUUIDRowIsSkipped() throws {
        let response = try decode(payload(rows: [
            goodRow(id: "not-a-uuid"),
            goodRow(id: idB),
        ]))

        #expect(response.skippedRows.count == 1)
        #expect(response.items.map { $0.id.uuidString.lowercased() } == [idB])
    }

    @Test func malformedDateRowIsSkipped() throws {
        let response = try decode(payload(rows: [
            goodRow(id: idA, createdAt: "yesterday-ish"),
            goodRow(id: idB),
        ]))

        #expect(response.skippedRows.count == 1)
        #expect(response.items.map { $0.id.uuidString.lowercased() } == [idB])
    }

    @Test func missingRequiredFieldRowIsSkipped() throws {
        let noTitle = """
        {
            "id": "\(idA)",
            "kind": "alert",
            "body": "Body",
            "priority": "high",
            "status": "pending",
            "createdAt": "2026-07-10T12:00:00Z"
        }
        """

        let response = try decode(payload(rows: [noTitle, goodRow(id: idB)]))

        #expect(response.skippedRows.count == 1)
        #expect(response.items.map { $0.id.uuidString.lowercased() } == [idB])
    }

    /// Rows that aren't even objects (string / null / number) must advance
    /// the decoder cleanly — the failure mode here would be an infinite loop
    /// or derailing the rows behind them.
    @Test func structurallyBizarreRowsAreSkipped() throws {
        let response = try decode(payload(rows: [
            "\"just a string\"",
            goodRow(id: idA),
            "null",
            "42",
            goodRow(id: idB),
        ]))

        #expect(response.skippedRows.count == 3)
        #expect(response.items.map { $0.id.uuidString.lowercased() } == [idA, idB])
    }

    @Test func allBadRowsYieldEmptyInboxNotAnError() throws {
        // The pre-#58 behavior was a throw here → "relay offline" app-side.
        // All-bad rows now decode to an EMPTY inbox with the skip count.
        let response = try decode(payload(rows: [
            goodRow(id: idA, kind: "directive"),
            goodRow(id: idB, kind: "banana"),
        ]))

        #expect(response.items.isEmpty)
        #expect(response.skippedRows.count == 2)
    }

    // MARK: - Optional fields still round-trip

    @Test func optionalFieldsDecodeWhenPresent() throws {
        let full = """
        {
            "id": "\(idA)",
            "kind": "approval",
            "title": "Deploy?",
            "body": "Approve the deploy",
            "priority": "urgent",
            "status": "pending",
            "payload": {"target": "ojamd"},
            "createdAt": "2026-07-10T12:00:00.123Z",
            "primaryActionTitle": "Approve",
            "secondaryActionTitle": "Dismiss"
        }
        """

        let response = try decode(payload(rows: [full]))

        #expect(response.skippedRows.isEmpty)
        let item = try #require(response.items.first)
        #expect(item.payload == ["target": "ojamd"])
        #expect(item.primaryActionTitle == "Approve")
        #expect(item.secondaryActionTitle == "Dismiss")
    }
}

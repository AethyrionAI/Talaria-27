import Foundation
import Testing
@testable import Talaria

/// **#432 — a decode failure must never put response bytes in the log.**
///
/// Two sites (`fetchSessionList` and `fetchStoredMessagesResponse`) decoded a
/// Hermes response, and on failure logged `String(data: data.prefix(500), …)`
/// at `.error` with `privacy: .public` — un-gated, and `.error` is exactly the
/// level `log collect` / sysdiagnose persists. The bodies those two calls hold
/// are the session LIST (titles + previews) and one session's STORED MESSAGES
/// (transcript text), and the branch fires on version skew or a proxy error
/// page — the moment a real transcript is most likely to be sitting in the
/// buffer. #138-M had already pinned "the transcript's TEXT is never logged"
/// for the voice instruments; these two sites were outside its bound.
///
/// The fix is a pure formatter that CANNOT leak the body: it is handed a byte
/// COUNT, not the bytes. This file pins that in three layers —
///
///   1. the formatter's own rows (what it renders, and what it refuses to),
///   2. a canary driven through BOTH real call sites over the URLProtocol
///      stub, asserting the emitted line carries no character of a sentinel
///      planted in the malformed body,
///   3. a tree-wide source witness: no body-bytes binding under
///      `Talaria/Services/` may reach a `privacy: .public` log interpolation
///      *in the same file*.
///
/// Layer 3 is what stops the DECODE defect from regrowing somewhere this suite
/// has never heard of. It is not, and cannot be, a proof that no response body
/// reaches os_log — which the fix round below learned the expensive way.
///
/// **⟵ FIX ROUND 1 (2026-09-06) — the decode branch was never the only door.**
/// `SessionsHermesClient.ensureSuccess` folded 200 bytes of any non-2xx body
/// into `SessionsClientError.requestFailed`'s message, and six live log lines
/// interpolate a thrown error's `localizedDescription` at `privacy: .public`;
/// `CronJobService` carried the identical shape into a seventh. Bytes reached
/// the same device archive by THROW rather than by `Logger` — the one route a
/// line-based source witness structurally cannot follow, and which the first
/// round's report and tracker text both recorded as impossible. Both are now
/// closed at the source of the message (a formatter that never receives the
/// body), and layer 4 measures it:
///
///   4. two behavioural canaries over the SAME stub asserting that the THROWN
///      error's `localizedDescription` — the exact string those log lines
///      carry — holds no character of the sentinel.
@Suite("Decode-failure log lines (#432)", .serialized)
struct DecodeFailureLogLineTests {

    // MARK: - The source witness (432-B, structural half)

    /// The detector, as a pure function over one file's text so it can be run
    /// against a planted string as well as the tree — a witness with no
    /// positive control is a check that passes on an empty enumeration.
    ///
    /// It flags ONE shape: response bytes becoming a String
    /// (`String(data:…)` or `String(decoding:…as:)` — the only two
    /// initialisers that do it) and reaching a `privacy: .public`
    /// interpolation, either directly on the logging line or by way of a local
    /// bound earlier in the same file. `.prefix(` alone is deliberately NOT the
    /// trigger — the router's `String(describing: error).prefix(80)` lines are
    /// bounded error descriptions, not bodies, and a witness that reddened on
    /// those would be turned off within a week.
    ///
    /// **What it CANNOT see — stated because a witness read as wider than it is
    /// becomes a false assurance, which is exactly what happened (the fix
    /// round's finding, 2026-09-06):**
    ///
    ///   1. **Bytes that travel by THROW.** A local bound from bytes, folded
    ///      into an error's message, caught in another function and logged as
    ///      `error.localizedDescription` reaches os_log without ever touching
    ///      this pattern. `SessionsHermesClient.ensureSuccess` did exactly
    ///      that, and one of the six public log lines it fed sits a thousand
    ///      lines EARLIER in the same file — the lookback only runs backwards
    ///      from a log line, and for `ChatStore` / `ChatBackendRouter` the
    ///      chain crosses files entirely. That path is closed structurally
    ///      instead (the message never receives the body) and measured by
    ///      `aNonSuccessBodyNeverReachesTheThrownErrorMessage`, not here.
    ///   2. **Anything the line-based match misses.** A binding or an
    ///      interpolation split across lines, a binding that appears after its
    ///      use, a name that travels through a second local, or bytes reaching
    ///      a log line through a function call.
    ///   3. **Nothing about SCOPE.** A binding anywhere in a file and a public
    ///      interpolation of that name anywhere later in it count as a hit even
    ///      in unrelated functions. Deliberate: the privacy stakes favour a
    ///      false positive, and the failure message says how to satisfy it.
    static func bodyBytesInPublicLogHits(in source: String, fileName: String) -> [String] {
        let lines = source.components(separatedBy: "\n")
        // Locals bound from raw bytes: `let x = String(data: …` /
        // `var x = …String(decoding:…` / `guard let x = String(data: …`.
        var byteBoundNames: [(name: String, line: Int)] = []
        for (index, line) in lines.enumerated() where namesRawBytes(line) {
            guard let binding = line.range(of: #"(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*="#,
                                           options: .regularExpression) else { continue }
            let declaration = String(line[binding])
            guard let nameRange = declaration.range(of: #"[A-Za-z_][A-Za-z0-9_]*\s*=$"#,
                                                    options: .regularExpression) else { continue }
            let name = declaration[nameRange]
                .replacingOccurrences(of: "=", with: "")
                .trimmingCharacters(in: .whitespaces)
            byteBoundNames.append((name, index))
        }

        var hits: [String] = []
        for (index, line) in lines.enumerated() where line.contains("privacy: .public") {
            if namesRawBytes(line) {
                hits.append("\(fileName):\(index + 1) — response bytes (String(data:)/String(decoding:)) interpolated at privacy: .public")
                continue
            }
            // One hit per offending LINE: the same local name can be bound
            // from bytes more than once in a file, and reporting the line
            // three times reads as three defects.
            if let bound = byteBoundNames.last(where: { $0.line < index && interpolates($0.name, in: line) }) {
                hits.append("\(fileName):\(index + 1) — '\(bound.name)' (bound from response bytes at line \(bound.line + 1)) interpolated at privacy: .public")
            }
        }
        return hits
    }

    /// The two initialisers that turn raw response bytes into a String.
    /// `String(decoding:as:)` was absent from this detector until 2026-09-06;
    /// seven live sites use it and none is public today, which is the state the
    /// witness exists to keep.
    private static func namesRawBytes(_ line: String) -> Bool {
        line.contains("String(data:") || line.contains("String(decoding:")
    }

    /// `\(name` with the name ending at a non-identifier character, so `\(id,`
    /// does not match a local called `idle`.
    private static func interpolates(_ name: String, in line: String) -> Bool {
        let needle = #"\("# + name
        var searchRange = line.startIndex ..< line.endIndex
        while let found = line.range(of: needle, range: searchRange) {
            let after = found.upperBound
            if after == line.endIndex {
                return true
            }
            let next = line[after]
            if !(next.isLetter || next.isNumber || next == "_") {
                return true
            }
            searchRange = after ..< line.endIndex
        }
        return false
    }

    /// The positive control. Without it, an enumeration that silently returned
    /// nothing would read exactly like a clean tree — the founding sin of this
    /// project's gate, arriving as a green source scan.
    @Test("the witness flags the pre-fix shape (positive control)")
    func theWitnessFlagsThePreFixShape() {
        let planted = #"""
        do {
            response = try decoder.decode(SessionsListResponse.self, from: data)
        } catch {
            let snippet = String(data: data.prefix(500), encoding: .utf8) ?? "(binary)"
            Self.logger.error("listSessions: decode FAILED — \(error.localizedDescription, privacy: .public). Raw: \(snippet, privacy: .public)")
            throw error
        }
        """#
        let hits = Self.bodyBytesInPublicLogHits(in: planted, fileName: "Planted.swift")
        #expect(hits.count == 1, "the witness did not see the very line #432 is about: \(hits)")
        #expect(hits.first?.contains("snippet") == true)
    }

    /// The direct shape too — a future site that skips the local and
    /// interpolates the decode inline must not walk past the witness.
    @Test("the witness flags an inline String(data:) at privacy: .public")
    func theWitnessFlagsTheInlineShape() {
        let planted = #"""
        logger.error("boom: \(String(data: data, encoding: .utf8) ?? "", privacy: .public)")
        """#
        #expect(Self.bodyBytesInPublicLogHits(in: planted, fileName: "Planted.swift").count == 1)
    }

    /// The discriminator, and the reason the witness keys on `String(data:`
    /// rather than on `.prefix(`: four live router lines log a bounded
    /// `String(describing: error)` publicly and are NOT this defect. A witness
    /// that reddened on them would be a witness someone deletes.
    @Test("a bounded error description at privacy: .public is not a hit")
    func aBoundedErrorDescriptionIsNotAHit() {
        let planted = #"""
        Self.logger.notice("router: classification failed — failing safe to armed (\(String(String(describing: error).prefix(80)), privacy: .public)) (#196)")
        """#
        #expect(Self.bodyBytesInPublicLogHits(in: planted, fileName: "Planted.swift").isEmpty)
    }

    /// **Minor from the fix round's review.** `String(decoding: data, as:
    /// UTF8.self)` is the OTHER way response bytes become a String, and the
    /// detector did not know the shape at all. Seven live sites use it (the
    /// runs transport's `classifySteerSubmit` / `classifyApprovalAnswer` /
    /// usage decode, `LiveVoiceSessionService`, `AttachmentInlining`,
    /// `LocalChatBackend`) and not one is public today — but "none today" is
    /// the thing this witness exists to keep true.
    @Test("the witness flags a String(decoding:) binding at privacy: .public")
    func theWitnessFlagsTheDecodingInitialiser() {
        let bound = #"""
        let bodyText = String(decoding: body, as: UTF8.self)
        Self.logger.error("runs: rejected — \(bodyText, privacy: .public)")
        """#
        let boundHits = Self.bodyBytesInPublicLogHits(in: bound, fileName: "Planted.swift")
        #expect(boundHits.count == 1, "the witness cannot see a String(decoding:) binding: \(boundHits)")
        #expect(boundHits.first?.contains("bodyText") == true)

        let inline = #"""
        logger.error("boom: \(String(decoding: data, as: UTF8.self), privacy: .public)")
        """#
        #expect(Self.bodyBytesInPublicLogHits(in: inline, fileName: "Planted.swift").count == 1)
    }

    /// A local bound from bytes and folded into a THROWN error is **outside
    /// the detector's reach — which is not the same as outside the app's.**
    ///
    /// This row's docstring used to say the shape "never reaches os_log", and
    /// that was FALSE: `SessionsHermesClient.ensureSuccess`'s message is
    /// interpolated at `privacy: .public` by six live log lines, and
    /// `CronJobService`'s by `deliverPlatforms()`. Both are closed
    /// structurally now, and the bars that measure it are
    /// `aNonSuccessBodyNeverReachesTheThrownErrorMessage` and its cron twin.
    ///
    /// The row stays, because pinning the BOUNDARY honestly is worth a test: a
    /// line-based scanner cannot follow bytes through a throw, a catch and
    /// another function, so this family can only ever be closed at the source
    /// of the message. `SkillsService` and `InsightsService` still build such
    /// a message; measured 2026-09-06, their errors reach `SkillsStore` /
    /// `InsightsStore` / `HostFailurePresentation` and no `privacy: .public`
    /// log line — that is why they are left, and it is a fact with a date on
    /// it rather than a property of the shape.
    @Test("bytes folded into a thrown error are outside the detector's reach")
    func bytesFoldedIntoAThrownErrorAreOutsideTheDetectorsReach() {
        let planted = #"""
        let bodySnippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
        throw SessionsClientError.requestFailed("Hermes API returned status \(httpResponse.statusCode). \(bodySnippet)")
        """#
        #expect(Self.bodyBytesInPublicLogHits(in: planted, fileName: "Planted.swift").isEmpty)
    }

    /// **The tree-wide bar — and its name is now literal on purpose.**
    ///
    /// It measures ONE shape: a body-bytes binding (or an inline decode)
    /// reaching a `privacy: .public` interpolation *later in the same file*.
    /// It was called `noResponseBodyReachesAPublicLogLine` until 2026-09-06,
    /// and that name asserted something it cannot check — a response body DID
    /// reach a public log line the whole time it said otherwise, through
    /// `ensureSuccess`'s thrown message. A test's name is read far more often
    /// than its detector, so the name is the claim. See
    /// `bodyBytesInPublicLogHits`' docstring for the three shapes it cannot
    /// see, and the two `…NeverReachesTheThrownErrorMessage` rows for the one
    /// that mattered.
    ///
    /// Fails loudly if the enumeration comes back empty — a check that could
    /// not run must say so rather than pass.
    @Test("no body-bytes binding reaches a public log line in the same file (Talaria/Services/)")
    func noBodyBytesBindingReachesAPublicLogLineInTheSameFile() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Talaria")
            .appendingPathComponent("Services")
        let files = try #require(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" },
            "cannot enumerate Talaria/Services/ — this check did not run"
        )
        #expect(files.count > 20, "only \(files.count) sources enumerated — this check did not really run")

        var hits: [String] = []
        for file in files {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else {
                Issue.record("cannot read \(file.lastPathComponent) — this check did not run over it")
                continue
            }
            hits.append(contentsOf: Self.bodyBytesInPublicLogHits(in: source, fileName: file.lastPathComponent))
        }
        #expect(hits.isEmpty, """
            response bytes reach a public log line (#432):
            \(hits.joined(separator: "\n"))
            Log structural metadata instead — route, status, byte count, the
            DecodingError's case and coding path. If a local genuinely holds
            no body, rename it away from a String(data:) binding.
            """)
    }

    // MARK: - The formatter (432-A)

    /// A `CodingKey` the rows can build a path out of — the real ones come
    /// from JSONDecoder and are not constructible here.
    private struct PathKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init(_ name: String) { stringValue = name; intValue = nil }
        init(index: Int) { stringValue = "Index \(index)"; intValue = index }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { self.init(index: intValue) }
    }

    private static func context(_ path: [any CodingKey], _ debug: String = "unused") -> DecodingError.Context {
        DecodingError.Context(codingPath: path, debugDescription: debug)
    }

    /// The WHOLE shape is pinned, not just its fields: a reader greps this
    /// line, and a reordered or extra field breaks someone who never runs
    /// this suite. Same discipline as the #138 segment lines.
    @Test("keyNotFound renders route, status, content type, byte count and a dotted key path")
    func keyNotFoundRendersTheWholeLine() {
        let error = DecodingError.keyNotFound(
            PathKey("id"),
            Self.context([PathKey("data"), PathKey(index: 0)])
        )
        let line = SessionsHermesClient.decodeFailureLogDetail(
            route: "/api/sessions",
            status: 200,
            contentType: "application/json",
            byteCount: 1234,
            error: error
        )
        #expect(line == "#432 decode FAILED route=/api/sessions status=200 contentType=application/json bytes=1234 case=keyNotFound key=data[0].id")
    }

    @Test("typeMismatch names the expected type and the key it tripped on")
    func typeMismatchNamesTheExpectedType() {
        let error = DecodingError.typeMismatch(
            String.self,
            Self.context([PathKey("data"), PathKey(index: 0), PathKey("role")])
        )
        let line = SessionsHermesClient.decodeFailureLogDetail(
            route: "/api/sessions/{id}/messages",
            status: 200,
            contentType: "application/json",
            byteCount: 77,
            error: error
        )
        #expect(line.contains("case=typeMismatch"))
        #expect(line.contains("key=data[0].role"))
        #expect(line.contains("expected=String"))
    }

    @Test("valueNotFound carries its type and path too")
    func valueNotFoundCarriesTypeAndPath() {
        let error = DecodingError.valueNotFound(
            Int.self,
            Self.context([PathKey("data"), PathKey(index: 3), PathKey("message_count")])
        )
        let line = SessionsHermesClient.decodeFailureLogDetail(
            route: "/api/sessions", status: 200, contentType: nil, byteCount: 0, error: error
        )
        #expect(line.contains("case=valueNotFound"))
        #expect(line.contains("key=data[3].message_count"))
        #expect(line.contains("expected=Int"))
    }

    /// **The reason no `debugDescription` is rendered anywhere.** Cocoa's own
    /// `dataCorrupted` for malformed JSON carries an underlying error whose
    /// text quotes a CHARACTER FROM THE BODY and its column — measured, not
    /// assumed (probe 2026-09-06: *"Unexpected character 'o' in expected null
    /// value around line 1, column 2."*). Folding the error's description into
    /// the line would have reopened #432 through the back door.
    @Test("a real dataCorrupted leaks neither the body character nor the column")
    func dataCorruptedLeaksNothingFromTheBody() throws {
        let malformed = Data("oops CANARY-SECRET".utf8)
        var thrown: Error?
        do {
            _ = try JSONDecoder().decode(SessionsHermesClient.SessionMessagesResponse.self, from: malformed)
        } catch {
            thrown = error
        }
        let error = try #require(thrown)
        let line = SessionsHermesClient.decodeFailureLogDetail(
            route: "/api/sessions", status: 502, contentType: "text/html", byteCount: malformed.count, error: error
        )
        #expect(line.contains("case=dataCorrupted"))
        #expect(line.contains("key=(root)"))
        #expect(line.contains("bytes=18"))
        #expect(!line.contains("CANARY"))
        #expect(!line.contains("Unexpected"))
        #expect(!line.contains("column"))
        #expect(!line.lowercased().contains("oops"))
    }

    /// A non-`DecodingError` gets its TYPE named and nothing else. Its
    /// `localizedDescription` is not ours to trust — the one above proves a
    /// framework error can quote the payload.
    @Test("a non-DecodingError names only its type, never its message")
    func aNonDecodingErrorNamesOnlyItsType() {
        struct Chatty: Error, LocalizedError {
            var errorDescription: String? { "CANARY-SECRET-7f3a leaked through localizedDescription" }
        }
        let line = SessionsHermesClient.decodeFailureLogDetail(
            route: "/api/sessions", status: 200, contentType: "application/json", byteCount: 9, error: Chatty()
        )
        #expect(line.contains("case=other"))
        #expect(line.contains("errorType=Chatty"))
        #expect(!line.contains("CANARY"))
        #expect(!line.contains("leaked"))
    }

    /// `none` and an empty value are opposite readings — a blank `status=`
    /// would say the response had no status, which is a claim, while `none`
    /// says the reader could not see one. Same pairing #138-M pinned for
    /// `offsetFromPlaybackMs`.
    @Test("an absent status and content type read none, never blank")
    func absentStatusAndContentTypeReadNone() {
        let line = SessionsHermesClient.decodeFailureLogDetail(
            route: "/api/sessions",
            status: nil,
            contentType: nil,
            byteCount: 0,
            error: DecodingError.dataCorrupted(Self.context([]))
        )
        #expect(line.contains("status=none"))
        #expect(line.contains("contentType=none"))
        #expect(line.contains("bytes=0"))
        #expect(!line.contains("status= "))
        #expect(!line.contains("contentType= "))
    }

    /// The content type is a SERVER-CHOSEN string. It is bounded and stripped
    /// of whitespace so one header can neither run away with the line nor
    /// forge extra `key=value` fields in it.
    @Test("the content type is bounded and cannot forge extra fields")
    func theContentTypeIsBoundedAndWhitespaceFree() {
        let hostile = "text/html; charset=utf-8 bytes=0 case=none " + String(repeating: "x", count: 300)
        let line = SessionsHermesClient.decodeFailureLogDetail(
            route: "/api/sessions", status: 502, contentType: hostile, byteCount: 41,
            error: DecodingError.dataCorrupted(Self.context([]))
        )
        let fields = line.components(separatedBy: " ")
        let value = (fields.first { $0.hasPrefix("contentType=") } ?? "")
            .replacingOccurrences(of: "contentType=", with: "")
        #expect(value.count <= 64)
        #expect(!value.isEmpty)
        // The forged fields did not survive as FIELDS — the header collapsed
        // into one whitespace-free token, so the line still has exactly one
        // `bytes=` and one `case=` of its own.
        #expect(fields.filter { $0.hasPrefix("bytes=") }.count == 1)
        #expect(fields.filter { $0.hasPrefix("case=") }.count == 1)
        #expect(line.contains(" bytes=41 "))
    }

    /// Defence in depth: no model these two routes decode has a
    /// dictionary-keyed field today, so every path component is one of OUR key
    /// names — but a future `[String: T]` would put a SERVER-CHOSEN key here,
    /// and this is the line that must stay boring.
    @Test("a long key name and a deep path are both bounded")
    func longKeyNamesAndDeepPathsAreBounded() {
        let long = String(repeating: "k", count: 200)
        let deep = (0 ..< 20).map { PathKey("level\($0)") }
        let shallow = SessionsHermesClient.decodeFailureLogDetail(
            route: "/api/sessions", status: 200, contentType: nil, byteCount: 1,
            error: DecodingError.keyNotFound(PathKey(long), Self.context([]))
        )
        #expect(!shallow.contains(String(repeating: "k", count: 40)))
        #expect(shallow.contains("…"))

        let nested = SessionsHermesClient.decodeFailureLogDetail(
            route: "/api/sessions", status: 200, contentType: nil, byteCount: 1,
            error: DecodingError.dataCorrupted(Self.context(deep))
        )
        #expect(!nested.contains("level9"))
        #expect(nested.contains("level0"))
        #expect(nested.contains("…"))
    }

    // MARK: - The non-2xx message formatter (fix round 1)

    /// The whole shape, pinned by equality for the same reason the decode line
    /// is: a reader greps it, and the six public log lines that carry it print
    /// it verbatim.
    @Test("the non-2xx message renders lead, status, content type and byte count")
    func hostStatusFailureDetailRendersTheWholeLine() {
        #expect(
            SessionsHermesClient.hostStatusFailureDetail(
                lead: "Hermes API", status: 502,
                contentType: "text/html; charset=utf-8", byteCount: 1234
            ) == "Hermes API returned status 502 — contentType=text/html;charset=utf-8, bytes=1234."
        )
        // Each service keeps its own voice over one shared, body-free tail.
        #expect(
            SessionsHermesClient.hostStatusFailureDetail(
                lead: "The Hermes host", status: 500,
                contentType: "application/json", byteCount: 0
            ) == "The Hermes host returned status 500 — contentType=application/json, bytes=0."
        )
    }

    /// `none` and blank are opposite readings here too — the same pairing the
    /// decode line makes, and it must not drift between the two formatters.
    @Test("an absent content type reads none in the non-2xx message")
    func hostStatusFailureDetailReadsNoneNotBlank() {
        let line = SessionsHermesClient.hostStatusFailureDetail(
            lead: "Hermes API", status: 418, contentType: nil, byteCount: 7
        )
        #expect(line.contains("contentType=none"))
        #expect(!line.contains("contentType=,"))
    }

    /// The `Content-Type` is server-chosen on this path too, so it rides the
    /// SAME `boundedContentType` the decode line uses — one helper, one bound,
    /// no second thing to keep in step.
    @Test("the non-2xx message bounds a hostile content type identically")
    func hostStatusFailureDetailBoundsAHostileContentType() {
        let hostile = "text/html; charset=utf-8 bytes=0 status=200 " + String(repeating: "x", count: 300)
        let line = SessionsHermesClient.hostStatusFailureDetail(
            lead: "Hermes API", status: 502, contentType: hostile, byteCount: 41
        )
        let fields = line.components(separatedBy: " ")
        let value = (fields.first { $0.hasPrefix("contentType=") } ?? "")
            .replacingOccurrences(of: "contentType=", with: "")
            .replacingOccurrences(of: ",", with: "")
        #expect(value.count <= 64)
        #expect(!value.isEmpty)
        // The forged fields did not survive AS fields: the header collapsed to
        // one whitespace-free token, so the line still carries exactly one
        // `bytes=` and one `status=` of its own.
        #expect(fields.filter { $0.hasPrefix("bytes=") }.count == 1)
        #expect(fields.filter { $0.hasPrefix("status") }.count == 1)
        #expect(line.hasSuffix("bytes=41."))
    }

    // MARK: - The canary through both real sites (432-B)

    /// #138-M's shape, moved onto the chat plane. The sentinel's CJK half is
    /// deliberate: none of its characters can appear incidentally in the
    /// line's own field names, so a leak of even ONE character is unambiguous.
    private static let sentinel = "CANARY-SECRET-7f3a-\u{54C8}\u{54C8}"   // 哈哈

    /// URLSession does not flush a custom protocol's body below ~512 bytes
    /// (probed 2026-08-03), so a short malformed body would never reach the
    /// decoder and the canary would pass for the wrong reason.
    ///
    /// **The padding goes LAST, and that placement is load-bearing.** With the
    /// pad first, the sentinel sat past byte 500 — so when the mutation
    /// reintroduced a `prefix(500)` snippet, only the padding leaked and every
    /// sentinel assertion passed while the body was in the log. Measured on
    /// this lane's first M1 run: the two canaries reddened on `ppppp` alone.
    /// A leak assertion that the mutation cannot fire is not an assertion.
    private static func padded(_ json: String) -> String {
        let padding = String(repeating: "p", count: 700)
        return json.replacingOccurrences(of: "__PAD__", with: padding)
    }

    private final class LineBox { var lines: [String] = [] }

    private final class CanaryStubURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    @MainActor
    private func makeClient(_ label: String) -> SessionsHermesClient {
        let suiteName = "decode-fail-\(label)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let persistence = UserDefaultsAppPersistenceStore(defaults: defaults)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CanaryStubURLProtocol.self]
        return SessionsHermesClient(
            baseURLProvider: { "http://ojamd:8642" },
            apiKeyProvider: { "key-test" },
            journal: ConversationJournalStore(persistence: persistence),
            transplanter: ContextTransplanter(intelligence: LocalIntelligenceService()),
            session: URLSession(configuration: configuration)
        )
    }

    /// Every character of the sentinel's CJK half, individually — the #138-M
    /// assertion, because a partial or re-encoded leak is still a leak.
    private func assertNoLeak(_ line: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(!line.contains(Self.sentinel), "the sentinel reached the log line", sourceLocation: sourceLocation)
        for character in "\u{54C8}\u{54C8}" {
            #expect(!line.contains(character), "a sentinel character reached the log line", sourceLocation: sourceLocation)
        }
        #expect(!line.contains("CANARY"), sourceLocation: sourceLocation)
        #expect(!line.contains("ppppp"), "the response body reached the log line", sourceLocation: sourceLocation)
    }

    @Test("the session-list decode failure logs metadata, never the body")
    @MainActor
    func theSessionListSiteLogsNoBodyBytes() async {
        let client = makeClient("list")
        let body = Self.padded(#"{"data": [{"title": "\#(Self.sentinel)", "preview": "\#(Self.sentinel)"}], "pad": "__PAD__"}"#)
        let bytes = Data(body.utf8)
        CanaryStubURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                             headerFields: ["Content-Type": "application/json"])!, bytes)
        }
        let box = LineBox()
        SessionsHermesClient.decodeFailureLogObserver = { box.lines.append($0) }
        defer {
            SessionsHermesClient.decodeFailureLogObserver = nil
            CanaryStubURLProtocol.requestHandler = nil
        }

        await #expect(throws: (any Error).self) { try await client.listSessions() }

        #expect(box.lines.count == 1, "the site emitted \(box.lines.count) lines — the canary measured nothing")
        let line = box.lines.first ?? ""
        assertNoLeak(line)
        #expect(line.contains("route=/api/sessions"))
        #expect(line.contains("status=200"))
        #expect(line.contains("bytes=\(bytes.count)"))
        #expect(line.contains("case=keyNotFound"))
        #expect(line.contains("key=data[0].id"))
    }

    @Test("the stored-messages decode failure logs metadata, never the transcript")
    @MainActor
    func theStoredMessagesSiteLogsNoBodyBytes() async {
        let client = makeClient("messages")
        let body = Self.padded(#"{"session_id": "api_x", "data": [{"role": 42, "content": "\#(Self.sentinel)"}], "pad": "__PAD__"}"#)
        let bytes = Data(body.utf8)
        CanaryStubURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                             headerFields: ["Content-Type": "application/json"])!, bytes)
        }
        let box = LineBox()
        SessionsHermesClient.decodeFailureLogObserver = { box.lines.append($0) }
        defer {
            SessionsHermesClient.decodeFailureLogObserver = nil
            CanaryStubURLProtocol.requestHandler = nil
        }

        await #expect(throws: (any Error).self) {
            _ = try await client.fetchStoredMessages("api_x-CANARY-id", profileID: nil)
        }

        #expect(box.lines.count == 1, "the site emitted \(box.lines.count) lines — the canary measured nothing")
        let line = box.lines.first ?? ""
        assertNoLeak(line)
        // The session id is no longer logged either: the old line named it
        // `.public` alongside the body, and the templated route is what a
        // reader debugging version skew actually needs.
        #expect(line.contains("route=/api/sessions/{id}/messages"))
        #expect(!line.contains("api_x"))
        #expect(line.contains("bytes=\(bytes.count)"))
        #expect(line.contains("case=typeMismatch"))
        #expect(line.contains("key=data[0].role"))
    }

    // MARK: - The root of the family (fix round 1)

    /// **The decode branch was never the only way response bytes reached
    /// os_log from this client, and the first round's report said it was.**
    ///
    /// `ensureSuccess` folded `String(data: data, encoding: .utf8)?.prefix(200)`
    /// into `SessionsClientError.requestFailed`'s message on every non-2xx.
    /// `SessionsClientError` is a `LocalizedError` that returns that message
    /// verbatim as `errorDescription`, and four live call sites interpolate a
    /// thrown error's `localizedDescription` at `privacy: .public`:
    /// `SessionsHermesClient.swift`'s own per-profile `listSessions` breadcrumb
    /// (`.notice` — which `log collect` and sysdiagnose persist exactly as
    /// `.error` does), `ChatStore.loadSessions`' two failure lines, and
    /// `ChatBackendRouter`'s no-host-answered line. The runs transport's
    /// turn-failure line makes a fifth. So the bytes arrived at the same place
    /// #432 was written to close, one function further along.
    ///
    /// The source witness below **cannot** see this and no line-based witness
    /// could: the binding is in `ensureSuccess`, the throw is there, the catch
    /// is in a different function, and the log line is over a thousand lines
    /// EARLIER in the file — the detector only looks backwards from a log
    /// line, and for `ChatStore`/`ChatBackendRouter` the chain crosses files.
    /// That is why the fix is structural (the message is built from status,
    /// content type and byte count and never receives the body) and why this
    /// bar is measured on BEHAVIOUR — the thrown error's own user-facing text,
    /// which is the exact string those five log lines carry.
    @Test("a non-2xx body never reaches the thrown error's message")
    @MainActor
    func aNonSuccessBodyNeverReachesTheThrownErrorMessage() async throws {
        let client = makeClient("status")
        // The sentinel sits in the first 200 bytes on purpose: `prefix(200)` is
        // what the pre-fix code took, so a sentinel past that offset would make
        // this assertion unfireable — the same defect the padding placement
        // above was written to fix.
        let body = Self.padded("upstream error: \(Self.sentinel) __PAD__")
        let bytes = Data(body.utf8)
        CanaryStubURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: "HTTP/1.1",
                             headerFields: ["Content-Type": "text/html; charset=utf-8"])!, bytes)
        }
        defer { CanaryStubURLProtocol.requestHandler = nil }

        var thrown: Error?
        do {
            _ = try await client.listSessions()
        } catch {
            thrown = error
        }
        let error = try #require(thrown, "the 502 did not throw — the canary measured nothing")
        // `localizedDescription`, not the case payload: that is what every one
        // of the five public log lines interpolates.
        let message = error.localizedDescription
        assertNoLeak(message)
        #expect(message.contains("502"))
        #expect(message.contains("bytes=\(bytes.count)"))
        #expect(message.contains("contentType=text/html;charset=utf-8"))
    }

    /// **The sibling the first round listed as safe, MEASURED 2026-09-06 and
    /// it is not.** `CronJobService.ensureSuccess` builds the same snippet
    /// (`CronJobService.swift`, the `default:` arm) into
    /// `CronJobServiceError.serverRejected`, and `deliverPlatforms()` catches
    /// that error and logs `error.localizedDescription` at `privacy: .public`
    /// on `.notice`. So a non-2xx from `GET /health/detailed` puts up to 200
    /// bytes of that response into a device archive — the same defect, one
    /// file over, on a path nothing had traced.
    ///
    /// `listJobs()` is the throwing entry point through the identical
    /// `ensureSuccess`, so the bar is measured on the error's own text — which
    /// is precisely the string `deliverPlatforms`' log line interpolates.
    ///
    /// **Deliberately NOT changed by this row:** the arm above it, which
    /// surfaces a decoded `error` FIELD untranslated. That is a structured
    /// server message and a product decision (the cron validation and
    /// schedule-parse messages users need); only the raw-bytes fallback is
    /// this defect.
    @Test("a non-2xx body never reaches the cron service's thrown message")
    @MainActor
    func aCronNonSuccessBodyNeverReachesTheThrownErrorMessage() async throws {
        let body = Self.padded("upstream error: \(Self.sentinel) __PAD__")
        let bytes = Data(body.utf8)
        CanaryStubURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 502, httpVersion: "HTTP/1.1",
                             headerFields: ["Content-Type": "text/html; charset=utf-8"])!, bytes)
        }
        defer { CanaryStubURLProtocol.requestHandler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CanaryStubURLProtocol.self]
        let service = CronJobService(
            baseURLProvider: { "http://ojamd:8642" },
            apiKeyProvider: { "key-test" },
            session: URLSession(configuration: configuration)
        )

        var thrown: Error?
        do {
            _ = try await service.listJobs()
        } catch {
            thrown = error
        }
        let error = try #require(thrown, "the 502 did not throw — the canary measured nothing")
        let message = error.localizedDescription
        assertNoLeak(message)
        #expect(message.contains("502"))
        #expect(message.contains("bytes=\(bytes.count)"))
        #expect(message.contains("contentType=text/html;charset=utf-8"))
    }
}

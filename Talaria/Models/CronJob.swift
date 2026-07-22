import Foundation

/// #156a — the agent's scheduled cron jobs, read from the Hermes gateway's
/// `/api/jobs` surface (same `:8642` + Bearer `API_SERVER_KEY` the chat path
/// uses).
///
/// Tolerant by construction: upstream is not contractual, so EVERY field is
/// optional, unknown fields are ignored, and a wrong-typed field degrades to
/// nil instead of throwing — a server field changing type must never blank
/// the Tasks screen. The one hard requirement is `id` (it addresses every
/// mutation endpoint); a record without a usable id is skipped at the list
/// level, never a decode failure for the whole fetch.
struct CronJob: Identifiable {
    let id: String
    var name: String?
    var prompt: String?
    var skills: [String]?
    var skill: String?
    var model: String?
    var provider: String?
    var providerSnapshot: String?
    var modelSnapshot: String?
    var baseURL: String?
    var script: String?
    var noAgent: Bool?
    var contextFrom: String?
    var schedule: CronSchedule?
    var scheduleDisplay: String?
    var repeatPolicy: CronRepeatPolicy?
    var enabled: Bool?
    var state: String?
    var pausedAt: String?
    var pausedReason: String?
    var createdAtRaw: String?
    var nextRunAtRaw: String?
    var lastRunAtRaw: String?
    var lastStatus: String?
    var lastError: String?
    var lastDeliveryError: String?
    var deliver: String?
    var enabledToolsets: [String]?
    var workdir: String?
    var attachToSession: Bool?
    var latestExecution: CronExecution?
}

/// Parsed schedule object (`{kind, display, minutes|expr|run_at}`). Verified
/// against hermes-agent 0.19.0 `cron/jobs.py parse_schedule`:
/// `kind` ∈ {"once", "interval", "cron"}. Tolerates a bare string (older or
/// hand-edited records) by treating it as the display.
struct CronSchedule {
    var kind: String?
    var display: String?
    var minutes: Int?
    var expr: String?
    var runAt: String?
}

/// `repeat` on the record: `{times, completed}` — `times` nil = forever.
/// Tolerates a bare integer (the shape the create/PATCH APIs accept).
struct CronRepeatPolicy {
    var times: Int?
    var completed: Int?
}

/// `latest_execution` attached by the server's list path (SQLite executions
/// row). `status` ∈ {claimed, running, completed, failed, unknown} — the
/// in-flight states are the client's only live "running" signal.
struct CronExecution {
    var id: String?
    var status: String?
    var claimedAt: String?
    var startedAt: String?
    var finishedAt: String?
    var error: String?

    var isInFlight: Bool {
        status == "running" || status == "claimed"
    }
}

// MARK: - Derived status

/// The server has no single status field — this is the client-side
/// aggregation the user actually needs (#156a D2, strongest idea from the
/// hermex review #160). `needsAttention` is the synthesized state: a
/// recurring job the server will never fire again without someone noticing
/// (e.g. croniter missing upstream leaves `state="error"`, `last_error` set,
/// no `next_run_at`, still enabled — deliberately "not silently disabled").
enum CronJobStatus: String, CaseIterable {
    case running
    case active
    case paused
    case off
    case error
    case needsAttention
}

extension CronJob {
    /// Recurring = the server will (should) keep firing it. Verified kinds:
    /// "interval" and "cron"; "once" is the only one-shot kind.
    var isRecurring: Bool {
        schedule?.kind == "interval" || schedule?.kind == "cron"
    }

    /// Server default is enabled — absent must not read as off.
    var isEnabled: Bool {
        enabled ?? true
    }

    var hasLastError: Bool {
        if lastStatus == "error" { return true }
        guard let lastError else { return false }
        return !lastError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Derivation order matters:
    /// 1. An in-flight execution outranks everything — it is happening now.
    /// 2. Paused is a deliberate user state (pause sets `enabled=false` too,
    ///    so it must be classified before the needsAttention/off branches
    ///    swallow it).
    /// 3. `state == "completed"` is a recurring job that finished its repeat
    ///    budget (verified upstream: `enabled=false, state="completed"`) —
    ///    that job did what was asked; it is off, not broken.
    /// 4. needsAttention: recurring + no server-side next run + (disabled or
    ///    errored) — the API never aggregates this; the UI must.
    /// 5. Errored-but-still-scheduled shows error; disabled shows off;
    ///    everything else is active.
    var derivedStatus: CronJobStatus {
        if latestExecution?.isInFlight == true { return .running }
        if state == "paused" { return .paused }
        if state == "completed" { return .off }
        if isRecurring, nextRunAtRaw == nil, !isEnabled || hasLastError {
            return .needsAttention
        }
        if hasLastError { return .error }
        if !isEnabled { return .off }
        return .active
    }

    /// Best display name — the server normalizes `name` on read, but a
    /// tolerant decode can still surface a blank.
    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? id : trimmed
    }

    /// The server-authoritative schedule text: `schedule_display` first,
    /// then the parsed object's `display`. Never client-derived (#156a D4).
    var scheduleText: String? {
        let candidates = [scheduleDisplay, schedule?.display]
        for candidate in candidates {
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    var createdAt: Date? { CronDateParsing.instant(from: createdAtRaw) }
    var nextRunAt: Date? { CronDateParsing.instant(from: nextRunAtRaw) }
    var lastRunAt: Date? { CronDateParsing.instant(from: lastRunAtRaw) }
}

// MARK: - Timestamp parsing

/// Hermes timestamps are Python `datetime.isoformat()` strings. Offset-carrying
/// values parse to real instants; a NAIVE string (no offset) is host-wall-clock
/// time in the *configured Hermes timezone*, which this device cannot resolve
/// to an instant — those stay raw and are labeled host time in the UI rather
/// than being silently misconverted (#156a timezone footgun).
enum CronDateParsing {
    /// Returns a Date only when the string carries an explicit UTC offset.
    static func instant(from raw: String?) -> Date? {
        guard let raw, hasExplicitOffset(raw) else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    /// True when the ISO string pins its own timezone ("Z" or ±HH:MM after
    /// the time part) — only then is device-local conversion honest.
    static func hasExplicitOffset(_ raw: String) -> Bool {
        guard let timeStart = raw.firstIndex(of: "T") else { return false }
        let timePart = raw[timeStart...]
        return timePart.contains("Z") || timePart.contains("+")
            || timePart.dropFirst().contains("-")
    }
}

// MARK: - Tolerant decoding

extension CronJob: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, prompt, skills, skill, model, provider
        case providerSnapshot = "provider_snapshot"
        case modelSnapshot = "model_snapshot"
        case baseURL = "base_url"
        case script
        case noAgent = "no_agent"
        case contextFrom = "context_from"
        case schedule
        case scheduleDisplay = "schedule_display"
        case repeatPolicy = "repeat"
        case enabled, state
        case pausedAt = "paused_at"
        case pausedReason = "paused_reason"
        case createdAt = "created_at"
        case nextRunAt = "next_run_at"
        case lastRunAt = "last_run_at"
        case lastStatus = "last_status"
        case lastError = "last_error"
        case lastDeliveryError = "last_delivery_error"
        case deliver
        case enabledToolsets = "enabled_toolsets"
        case workdir
        case attachToSession = "attach_to_session"
        case latestExecution = "latest_execution"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // id is the one load-bearing field — every mutation endpoint needs
        // it. Missing/blank throws so the LIST decode can skip just this row.
        guard let id = try? container.decode(String.self, forKey: .id),
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Cron job record has no usable id"
                )
            )
        }
        self.id = id
        name = try? container.decode(String.self, forKey: .name)
        prompt = try? container.decode(String.self, forKey: .prompt)
        skills = try? container.decode([String].self, forKey: .skills)
        skill = try? container.decode(String.self, forKey: .skill)
        model = try? container.decode(String.self, forKey: .model)
        provider = try? container.decode(String.self, forKey: .provider)
        providerSnapshot = try? container.decode(String.self, forKey: .providerSnapshot)
        modelSnapshot = try? container.decode(String.self, forKey: .modelSnapshot)
        baseURL = try? container.decode(String.self, forKey: .baseURL)
        script = try? container.decode(String.self, forKey: .script)
        noAgent = try? container.decode(Bool.self, forKey: .noAgent)
        contextFrom = try? container.decode(String.self, forKey: .contextFrom)
        schedule = try? container.decode(CronSchedule.self, forKey: .schedule)
        scheduleDisplay = try? container.decode(String.self, forKey: .scheduleDisplay)
        repeatPolicy = try? container.decode(CronRepeatPolicy.self, forKey: .repeatPolicy)
        enabled = try? container.decode(Bool.self, forKey: .enabled)
        state = try? container.decode(String.self, forKey: .state)
        pausedAt = try? container.decode(String.self, forKey: .pausedAt)
        pausedReason = try? container.decode(String.self, forKey: .pausedReason)
        createdAtRaw = try? container.decode(String.self, forKey: .createdAt)
        nextRunAtRaw = try? container.decode(String.self, forKey: .nextRunAt)
        lastRunAtRaw = try? container.decode(String.self, forKey: .lastRunAt)
        lastStatus = try? container.decode(String.self, forKey: .lastStatus)
        lastError = try? container.decode(String.self, forKey: .lastError)
        lastDeliveryError = try? container.decode(String.self, forKey: .lastDeliveryError)
        deliver = try? container.decode(String.self, forKey: .deliver)
        enabledToolsets = try? container.decode([String].self, forKey: .enabledToolsets)
        workdir = try? container.decode(String.self, forKey: .workdir)
        attachToSession = try? container.decode(Bool.self, forKey: .attachToSession)
        latestExecution = try? container.decode(CronExecution.self, forKey: .latestExecution)
    }
}

extension CronSchedule: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, display, minutes, expr
        case runAt = "run_at"
    }

    init(from decoder: any Decoder) throws {
        // A bare string is an older/hand-edited record's shape — keep it as
        // the display so the row still reads sensibly.
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self) {
            display = raw
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try? container.decode(String.self, forKey: .kind)
        display = try? container.decode(String.self, forKey: .display)
        minutes = CronLenientInt.decode(container, key: .minutes)
        expr = try? container.decode(String.self, forKey: .expr)
        runAt = try? container.decode(String.self, forKey: .runAt)
    }
}

extension CronRepeatPolicy: Decodable {
    private enum CodingKeys: String, CodingKey {
        case times, completed
    }

    init(from decoder: any Decoder) throws {
        // The write APIs accept a bare positive int — tolerate it on read
        // too, in case a record round-trips unnormalized.
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(Int.self) {
            times = raw
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        times = CronLenientInt.decode(container, key: .times)
        completed = CronLenientInt.decode(container, key: .completed)
    }
}

extension CronExecution: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, status, error
        case claimedAt = "claimed_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decode(String.self, forKey: .id)
        status = try? container.decode(String.self, forKey: .status)
        claimedAt = try? container.decode(String.self, forKey: .claimedAt)
        startedAt = try? container.decode(String.self, forKey: .startedAt)
        finishedAt = try? container.decode(String.self, forKey: .finishedAt)
        error = try? container.decode(String.self, forKey: .error)
    }
}

/// Int fields tolerate a numeric string or a float — degrade, don't throw.
private enum CronLenientInt {
    static func decode<K: CodingKey>(_ container: KeyedDecodingContainer<K>, key: K) -> Int? {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(Double.self, forKey: key) { return Int(value) }
        if let value = try? container.decode(String.self, forKey: key) { return Int(value) }
        return nil
    }
}

// MARK: - Wire envelopes

/// `GET /api/jobs` → `{"jobs": [...]}`, decoded row-by-row so one malformed
/// record (id missing after a server-side shape change) skips that row
/// instead of failing the whole fetch — same posture as the Inbox (#58).
struct CronJobListResponse: Decodable {
    let jobs: [CronJob]
    let skippedRowCount: Int

    private enum CodingKeys: String, CodingKey {
        case jobs
    }

    /// Never-throwing probe used to advance the unkeyed container past a bad
    /// row, whatever its JSON shape.
    private struct SkippedRow: Decodable {
        init() {}
        init(from decoder: any Decoder) {}
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var rows = try container.nestedUnkeyedContainer(forKey: .jobs)
        var decoded: [CronJob] = []
        var skipped = 0
        while !rows.isAtEnd {
            let indexBeforeRow = rows.currentIndex
            do {
                decoded.append(try rows.decode(CronJob.self))
            } catch {
                skipped += 1
                _ = try? rows.decode(SkippedRow.self)
                if rows.currentIndex == indexBeforeRow { break }
            }
        }
        jobs = decoded
        skippedRowCount = skipped
    }
}

/// Every mutation endpoint answers `{"job": {...}}` (verified 0.19.0);
/// DELETE answers `{"ok": true}`.
struct CronJobEnvelope: Decodable {
    let job: CronJob
}

struct CronOKResponse: Decodable {
    let ok: Bool?
}

/// Error bodies are `{"error": "<message>"}` — the message string must reach
/// the UI verbatim; the server is the only cron validator that exists.
struct CronErrorBody: Decodable {
    let error: String?
}

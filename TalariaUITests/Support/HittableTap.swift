import XCTest

/// **A tap whose FAILURE PATH describes itself in the log (#219, bar DET-A).**
///
/// The suite's oldest flake is a synthesized tap that lands without invoking
/// its action. Its measured signature (gate run 2026-09-03, `suite.log`) is
/// narrow and strange: the button EXISTS at a valid on-screen frame, reads
/// `isHittable == false` for the whole window, and XCUITest's own tap step
/// logs `Computed hit point {-1, -1} after scrolling to visible` — it could
/// find and measure the element and still resolve no point to touch.
///
/// The evidence for WHY has never been captured, and the reason is a lesson
/// rather than an accident: the one rich diagnostic the suite carried lived in
/// an `XCTAssertTrue` message, and that assertion PASSES on this shape (the
/// button exists), so its message is never printed. The `.xcresult` for the
/// same shape hangs, so the usual fallback is gone too. What DOES reach the
/// gate's `suite.log` is an `XCTContext.runActivity` NAME — proven, because
/// the one activity this flow already emitted (`XFLAKE pre …`) is in that log.
///
/// So every fact this helper collects is emitted as an activity name, each
/// prefixed `HITTAP ` so a script can grep the run apart, and each clamped to
/// 200 characters so no single line can swallow the log.
///
/// **Why the timeout path still taps.** A baseline the A/B can compare against
/// has to be today's behaviour, and today every one of these call sites taps
/// regardless of hittability. `.elementTap` IS that bare tap; the coordinate
/// arm is the single change the later measurement varies. Neither arm widens a
/// wait: each call site passes the budget it already had.
enum HittableTap {
    /// What to do when the poll never sees `exists && isHittable`.
    ///
    /// `elementTap` is today's behaviour (a bare `XCUIElement.tap()`).
    /// `coordinateAfterTimeout` taps the element's centre in the app's
    /// coordinate space instead — the arm the #219 A/B measures.
    enum Strategy: String, CustomStringConvertible {
        case elementTap
        case coordinateAfterTimeout

        var description: String { rawValue }
    }

    /// The tap that happened. `tappedAfterTimeout` carries the same content as
    /// the emitted activities, joined by newlines, so a caller can assert on
    /// the diagnostic without scraping the log.
    enum Outcome: Equatable, CustomStringConvertible {
        case tapped
        case tappedAfterTimeout(diagnostic: String, via: Strategy)

        var description: String {
            switch self {
            case .tapped:
                return "tapped"
            case .tappedAfterTimeout(_, let via):
                return "tappedAfterTimeout(via: \(via))"
            }
        }
    }

    /// Every activity this helper emits starts with this. The scripts-side
    /// batch instrument greps it; do not change it without changing that.
    static let activityPrefix = "HITTAP "

    /// Read from the TEST RUNNER's environment, which `xcodebuild` populates
    /// from `TEST_RUNNER_UITEST_TAP_STRATEGY`.
    static let strategyEnvironmentKey = "UITEST_TAP_STRATEGY"

    /// A grep is only useful while one match is one line.
    static let maximumActivityLength = 200

    /// The centre-point walk is a diagnostic, not a dump: enough to name what
    /// is on top, bounded so a deep hierarchy cannot flood the log.
    static let maximumElementsUnderPoint = 12

    static let pollInterval: TimeInterval = 0.25

    /// `"coordinate"` selects the coordinate arm; anything else (including
    /// unset) is today's behaviour. Fail-safe by construction — a typo in the
    /// environment measures the baseline rather than an unknown third thing.
    static var strategyFromEnvironment: Strategy {
        ProcessInfo.processInfo.environment[strategyEnvironmentKey] == "coordinate"
            ? .coordinateAfterTimeout
            : .elementTap
    }

    // MARK: - The hierarchy snapshot

    /// One accessibility element as it appears in a single `debugDescription`
    /// dump: what it is, what it is called, and where it sits.
    struct SnapshotRow: Equatable {
        let type: String
        let identifier: String
        let frame: CGRect
    }

    /// Parses `XCUIApplication.debugDescription` into rows.
    ///
    /// **This is the whole reason the walk reads a dump instead of querying
    /// elements.** `allElementsBoundByIndex` re-snapshots the hierarchy on
    /// every access and throws "No matches found for Element at index N" the
    /// moment the tree changes underneath — which is exactly what a screen mid
    /// -transition does, and it is how an earlier attempt at this diagnostic
    /// replaced a readable failure with an unreadable one (the comment above
    /// `advanceWizardToStartChatting`'s final assertion records that). One
    /// dump is one snapshot: internally consistent, and it cannot throw.
    ///
    /// Deliberately tolerant: any line without a frame is skipped rather than
    /// treated as a parse failure, so a dump-format change costs the walk its
    /// resolution, never the run.
    static func rows(fromDebugDescription dump: String) -> [SnapshotRow] {
        var rows: [SnapshotRow] = []
        for rawLine in dump.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            // The subtree section is what carries frames; the trailing
            // "Path to element" section repeats elements and would double-count.
            if line.hasPrefix("Path to element") { break }
            // The dump's ROOT line — `Attributes: Application, 0x…, pid: N,
            // label: '…'`. **Measured on this toolchain (Xcode-beta6, sim
            // runtime 24A5423a) it carries NO frame**, so it is skipped by the
            // frame guard below anyway; the explicit skip is here because a
            // shape that DOES print the application's frame there would parse
            // as a full-screen row whose type is the literal string
            // "Attributes:" — a phantom blocker over every centre point, sat
            // at index 1 where the walk is most likely to be read. The
            // application is not lost: it appears again in the subtree.
            // `HittableTapParserTests` pins both arms.
            if line.hasPrefix("Attributes:") { continue }
            guard let frame = frame(inLine: line) else { continue }
            rows.append(
                SnapshotRow(
                    type: elementType(inLine: line),
                    identifier: identifier(inLine: line),
                    frame: frame
                )
            )
        }
        return rows
    }

    /// `{{24.0, 509.0}, {372.0, 56.0}}` → `CGRect`.
    static func frame(inLine line: String) -> CGRect? {
        guard let open = line.range(of: "{{"),
              let close = line.range(of: "}}", range: open.upperBound..<line.endIndex)
        else { return nil }
        let body = line[open.upperBound..<close.lowerBound]
        let numbers = body
            .split(whereSeparator: { !"0123456789.-e".contains($0) })
            .compactMap { Double($0) }
        guard numbers.count == 4 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    /// The leading token: `Button`, `Other`, `Window`… Indentation, the dump's
    /// `→` root marker and a parenthetical qualifier (`Window (Main)`) are all
    /// noise for this purpose.
    static func elementType(inLine line: String) -> String {
        let head = line.prefix(while: { $0 != "," })
        let trimmed = head.trimmingCharacters(in: CharacterSet(charactersIn: " \t→"))
        return trimmed.split(separator: " ").first.map(String.init) ?? "?"
    }

    /// `identifier: 'connectHostWizard.startChatting'` → the bare identifier.
    /// Empty when the element has none — which is itself worth printing, since
    /// an unnamed full-screen `Other` on top is a common way to swallow a tap.
    static func identifier(inLine line: String) -> String {
        let marker = "identifier: '"
        guard let start = line.range(of: marker),
              let end = line.range(of: "'", range: start.upperBound..<line.endIndex)
        else { return "" }
        return String(line[start.upperBound..<end.lowerBound])
    }

    // MARK: - The diagnostic

    /// The DET-A bar, as activity names.
    ///
    /// Order matters for a reader scanning a 20,000-line gate log: what was
    /// asked for, what the app looked like, then what was actually sitting on
    /// the point we could not touch.
    static func diagnosticLines(
        for element: XCUIElement,
        label: String,
        in app: XCUIApplication,
        strategy: Strategy,
        timeout: TimeInterval
    ) -> [String] {
        var lines: [String] = []

        // Property reads on a MISSING element are not free — XCUITest fails the
        // test rather than returning a placeholder — so existence gates them.
        let exists = element.exists
        var elementFrame = CGRect.zero
        if exists {
            elementFrame = element.frame
            lines.append("""
                \(activityPrefix)pre \(label) exists=true hittable=\(element.isHittable) \
                enabled=\(element.isEnabled) selected=\(element.isSelected) \
                frame=\(describe(elementFrame))
                """)
        } else {
            lines.append("\(activityPrefix)pre \(label) exists=false — the element is not in the hierarchy at all")
        }

        // `firstMatch` property reads are gated: see `describeFrame(of:)`.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        lines.append("""
            \(activityPrefix)app \(label) state=\(describe(app.state)) windows=\(app.windows.count) \
            keyboards=\(app.keyboards.count) alerts=\(springboard.alerts.count) \
            buttons=\(app.buttons.count) window=\(describeFrame(of: app.windows.firstMatch)) \
            scroll=\(describeFrame(of: app.scrollViews.firstMatch))
            """)

        guard exists, !elementFrame.isEmpty else {
            lines.append("\(activityPrefix)under none reason=no-frame — nothing to walk")
            lines.append("\(activityPrefix)fallback \(label) via=\(strategy) under=0")
            return lines.map(clamp)
        }

        let centre = CGPoint(x: elementFrame.midX, y: elementFrame.midY)
        lines.append("""
            \(activityPrefix)centre \(label) point=(\(round(centre.x)), \(round(centre.y))) \
            strategy=\(strategy) timeout=\(timeout)s
            """)

        // ONE dump, one snapshot — see `rows(fromDebugDescription:)`.
        let covering = rows(fromDebugDescription: app.debugDescription)
            .filter { $0.frame.contains(centre) }
        // **Keep BOTH ENDS, not the tail.** Which end the blocker sits at is
        // not knowable in advance: SwiftUI reports a ZStack front-to-back, so
        // an un-prioritised layer on top lands at the HEAD — while THIS
        // fixture's overlay carries `.accessibilitySortPriority(-1000)`,
        // which is what puts it near the tail (measured: covering position
        // 14 of 19). A tail-only cap would have dropped the head case, and
        // naming the blocker is the bar. Cap unchanged at 12 (DET-A's number):
        // head 6 + tail 6.
        //
        // The printed index is ABSOLUTE — position within `covering`, over
        // `covering.count` — so a truncated list still says WHERE each row
        // sat. A shown-count denominator made `under[7/12]` look like the
        // whole list.
        let indexed = Array(covering.enumerated())
        let shown: [(offset: Int, element: SnapshotRow)]
        if indexed.count > maximumElementsUnderPoint {
            let half = maximumElementsUnderPoint / 2
            shown = Array(indexed.prefix(half)) + Array(indexed.suffix(half))
        } else {
            shown = indexed
        }
        if shown.isEmpty {
            lines.append("\(activityPrefix)under none — no element in the snapshot contains the centre point")
        }
        for entry in shown {
            lines.append("""
                \(activityPrefix)under[\(entry.offset + 1)/\(covering.count)] \(entry.element.type) \
                id=\(entry.element.identifier) frame=\(describe(entry.element.frame))
                """)
        }
        if covering.count > shown.count {
            let half = maximumElementsUnderPoint / 2
            lines.append("""
                \(activityPrefix)under truncated total=\(covering.count) shown=\(shown.count) \
                elided=\(half + 1)…\(covering.count - half)
                """)
        }
        lines.append("\(activityPrefix)fallback \(label) via=\(strategy) under=\(covering.count)")

        return lines.map(clamp)
    }

    static func clamp(_ line: String) -> String {
        let flattened = line.replacingOccurrences(of: "\n", with: " ")
        guard flattened.count > maximumActivityLength else { return flattened }
        return String(flattened.prefix(maximumActivityLength - 1)) + "…"
    }

    static func describe(_ rect: CGRect) -> String {
        "(\(rect.origin.x), \(rect.origin.y), \(rect.size.width), \(rect.size.height))"
    }

    /// **Every property read in a diagnostic is gated on existence.**
    ///
    /// A `firstMatch` that matches nothing raises "Failed to get matching
    /// snapshot" on ANY property read, and with `continueAfterFailure = false`
    /// that error replaces the dump with a stack trace — at exactly the moment
    /// the dump is the point. (Measured twice in this lane: once in the
    /// helper's `app.windows.firstMatch.frame`, once in a fixture's own
    /// failure message.) An absent element prints `-`.
    static func describeFrame(of element: XCUIElement) -> String {
        element.exists ? describe(element.frame) : "-"
    }

    /// Existence-gated `exists`/`hittable`/`frame` for a diagnostic message —
    /// same rule as `describeFrame(of:)`.
    static func describe(_ element: XCUIElement) -> String {
        guard element.exists else { return "exists=false" }
        return "exists=true hittable=\(element.isHittable) frame=\(describe(element.frame))"
    }

    static func describe(_ state: XCUIApplication.State) -> String {
        switch state {
        case .unknown: return "unknown"
        case .notRunning: return "notRunning"
        case .runningBackgroundSuspended: return "runningBackgroundSuspended"
        case .runningBackground: return "runningBackground"
        case .runningForeground: return "runningForeground"
        @unknown default: return "unhandled(\(state.rawValue))"
        }
    }
}

extension XCUIElement {
    /// Taps once the element is hittable, and says why it could not be when it
    /// never becomes so.
    ///
    /// - Parameters:
    ///   - timeout: the budget this CALL SITE already had. Pass `0` where the
    ///     existing code taps immediately — polling on borrowed time is how a
    ///     diagnostic turns into a hedge, and #219's falsified 5s `isHittable`
    ///     hedge is not being re-tried in any form.
    ///   - strategy: pass one explicitly to pin a site out of the A/B (a site
    ///     that already coordinate-taps keeps doing so); leave it defaulted at
    ///     the site the A/B varies.
    ///   - diagnose: `false` suppresses the dump (and the success token) for
    ///     this call, leaving ONE line on the timeout path. A retry loop that
    ///     calls this every second passes `false` once it already has a dump —
    ///     see the CONTINUE loop in `AppTemplateUITests`. It does not change
    ///     what is tapped or how long anything waits.
    ///   - label: what to call this tap in the log. Use the accessibility
    ///     identifier so a grep of the log meets the same string as a grep of
    ///     the source.
    @discardableResult
    @MainActor
    func tapWhenHittable(
        timeout: TimeInterval,
        in app: XCUIApplication,
        strategy: HittableTap.Strategy = HittableTap.strategyFromEnvironment,
        diagnose: Bool = true,
        label: String
    ) -> HittableTap.Outcome {
        let startedPolling = Date()
        let deadline = Date(timeIntervalSinceNow: timeout)
        var polls = 0
        while true {
            if exists, isHittable {
                // **STOP THE CLOCK BEFORE THE TAP.** `polledFor` names the
                // POLL, and a reading taken after `tap()` is the poll plus the
                // tap's own latency — measured at 0.78s on a site whose budget
                // is ZERO, i.e. a number that reported 0.78s of polling from a
                // loop that could not have polled at all. The readers of this
                // line separate "tapped on first look" from "self-healed
                // during the poll"; folding tap latency in makes the first of
                // those unrecognisable.
                let polledFor = Date().timeIntervalSince(startedPolling)
                tap()
                if diagnose {
                    // **The success path has to be separable too.** Without
                    // this line a tap that went out on the first look and one
                    // that went out at t = 9.9s are byte-identical in the log,
                    // and the A/B's whole question is which of those happened.
                    let waited = String(format: "%.2f", polledFor)
                    XCTContext.runActivity(named: HittableTap.clamp("""
                        \(HittableTap.activityPrefix)tapped \(label) via=\(strategy) \
                        polledFor=\(waited)s polls=\(polls) budget=\(timeout)s
                        """)) { _ in }
                }
                return .tapped
            }
            guard Date() < deadline else { break }
            polls += 1
            // Runloop-friendly: a blocking sleep on the main actor starves
            // XCTest's own machinery (the same reason `waitForCounter` polls
            // this way).
            RunLoop.current.run(until: Date(timeIntervalSinceNow: HittableTap.pollInterval))
        }

        // The suppressed arm: one line, no snapshot. A caller in a retry loop
        // would otherwise pay a full `debugDescription` and ~16 activities on
        // EVERY iteration of the flake the loop exists for — which both floods
        // the grepped prefix and eats the loop's own cadence.
        guard diagnose else {
            let line = HittableTap.clamp("""
                \(HittableTap.activityPrefix)fallback \(label) via=\(strategy) \
                diagnose=suppressed — a dump for this element was already emitted in this loop
                """)
            XCTContext.runActivity(named: line) { _ in }
            performFallbackTap(strategy)
            return .tappedAfterTimeout(diagnostic: line, via: strategy)
        }

        let lines = HittableTap.diagnosticLines(
            for: self, label: label, in: app, strategy: strategy, timeout: timeout
        )
        for line in lines {
            XCTContext.runActivity(named: line) { _ in }
        }

        performFallbackTap(strategy)
        return .tappedAfterTimeout(diagnostic: lines.joined(separator: "\n"), via: strategy)
    }

    /// Today's behaviour, deliberately: the tap goes out either way, so a
    /// baseline run measures the flake rather than a new refusal to tap.
    @MainActor
    private func performFallbackTap(_ strategy: HittableTap.Strategy) {
        switch strategy {
        case .elementTap:
            tap()
        case .coordinateAfterTimeout:
            coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }
}

extension XCTestCase {
    /// The chat composer surfaces as a text field or a text view depending on
    /// the SwiftUI editor in use — check the identifier and the accessibility
    /// label across both.
    ///
    /// Shared (#219): this and `waitForComposer` were byte-identical private
    /// copies in `AppTemplateUITests` and `MessageIdentityUITests`. Two copies
    /// of a locator is two places to fix when the composer's identity moves,
    /// and only one of them would have been found.
    @MainActor
    func composerInput(in app: XCUIApplication) -> XCUIElement {
        for candidate in [
            app.textFields["chat.composer"],
            app.textViews["chat.composer"],
            app.textFields["Reply to Hermes"],
            app.textViews["Reply to Hermes"],
        ] where candidate.exists {
            return candidate
        }
        return app.textViews["chat.composer"]
    }

    /// Polls the composer candidates until one exists (the screen may still be
    /// transitioning off onboarding when the first query runs), so the wait
    /// isn't pinned to a single element type guessed too early.
    ///
    /// **It deliberately does NOT poll hittability, and that is a stated
    /// deviation from #219's "poll `exists ∧ hittable`" shape** — recorded
    /// here rather than only in the lane report, because the next reader will
    /// otherwise repair it. Three reasons, all of them about meaning rather
    /// than convenience:
    /// - every caller reads a `nil` return as "chat never came up", and a
    ///   composer that exists but is not yet hittable is chat HAVING come up.
    ///   Adding the requirement would change 15 tests' failure semantics for
    ///   no measurement;
    /// - most callers never tap the result — they are landing checks;
    /// - the one caller that DOES tap (`MessageIdentityUITests.sendMessage`)
    ///   polls hittability at the tap itself, through `tapWhenHittable`. So
    ///   the property is asserted where it matters and no budget moves.
    /// Unchanged from both of the private originals this replaced.
    @MainActor
    func waitForComposer(in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            let candidate = composerInput(in: app)
            if candidate.exists { return candidate }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
        } while Date() < deadline
        return nil
    }
}

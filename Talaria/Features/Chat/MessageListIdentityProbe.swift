import SwiftUI

/// #120 (UITest seam): a zero-size, test-only accessibility probe that reports
/// the worst-case ID multiplicity of the rendered message collection — the
/// exact invariant the transcript `ForEach(messages)` depends on (SwiftUI
/// declares a duplicate-ID `ForEach` undefined).
///
/// XCUITest is black-box: it can't read `ChatStore.conversation.messages`
/// directly, and a duplicate `ForEach` id may render one row, drop one, or
/// glitch — so counting rendered rows is not a reliable detector. This probe
/// closes that gap deterministically: it reads the same array the `ForEach`
/// iterates and publishes `max(multiplicity)` as an accessibility value the
/// test can assert on (1 ⇒ unique; ≥2 ⇒ the #120 regression).
///
/// The probe is compiled into every build but only joins the view tree when
/// the `UITEST_DUPID_PROBE` launch environment is set, so shipping builds
/// never carry it. Gating is read once at construction (launch env is
/// immutable for the process lifetime).
struct MessageListIdentityProbe: View {
    /// The exact collection the transcript `ForEach` renders.
    let messages: [Message]

    /// Accessibility identifier the UITest queries.
    static let identifier = "chat.dupIDProbe"

    /// Launch-env gate. Inert (and absent from the tree) unless set.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["UITEST_DUPID_PROBE"] == "1"
    }

    /// Worst-case multiplicity of any message id in the rendered collection.
    /// 0 for an empty transcript, 1 when every id is unique, ≥2 iff a
    /// duplicate id reached the rendered array (the #120 failure).
    static func maxIDMultiplicity(_ messages: [Message]) -> Int {
        Dictionary(grouping: messages, by: \.id)
            .values
            .map(\.count)
            .max() ?? 0
    }

    var body: some View {
        if Self.isEnabled {
            // Zero-size and hidden from assistive tech, but still an
            // accessibility element the test can read by identifier. The
            // value updates on every render because `messages` is a view
            // input — it always mirrors what the sibling `ForEach` just drew.
            Color.clear
                .frame(width: 0, height: 0)
                .accessibilityElement()
                .accessibilityIdentifier(Self.identifier)
                .accessibilityValue("\(Self.maxIDMultiplicity(messages))")
                .accessibilityHidden(false)
                .allowsHitTesting(false)
        }
    }
}

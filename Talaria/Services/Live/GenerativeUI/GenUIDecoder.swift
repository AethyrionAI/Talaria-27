import Foundation

// MARK: - Tolerant IR ingestion
//
// Turns untrusted IR JSON into a sanitized `GenUISurface`, skip-and-log style:
// an unknown or malformed node is dropped (with a Console-visible log line) and
// its well-formed siblings survive — the whole tree is never rejected for one
// bad node, and nothing here can crash on bad input.
//
// This is the debug-harness and test ingestion path. The later model-wiring
// rung feeds guided generation through the strict `@Generable` initializers
// instead — where the schema itself prevents unknown kinds — and then applies
// the same `sanitized()` pass for the rules a schema can't express (nested
// rows, promptless buttons).
//
// Deliberately built on JSONSerialization + manual walking, not Codable:
// tolerance rules (default missing fields, skip unknown kinds, survive wrong
// types) are explicit here, and the `@Generable` types stay free of extra
// conformances the macro was never verified against.

enum GenUIDecoder {

    /// Decode a surface from IR JSON. Accepts either `{"blocks": [...]}` or a
    /// bare top-level array of blocks. Returns nil only when the top level is
    /// unusable; inside the tree, bad nodes are skipped and logged instead.
    static func surface(fromJSON json: String) -> GenUISurface? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            TalariaLog.event("GenUI: IR JSON is not parseable — no surface")
            return nil
        }

        let blockList: [Any]
        if let dict = root as? [String: Any], let list = dict["blocks"] as? [Any] {
            blockList = list
        } else if let list = root as? [Any] {
            blockList = list
        } else {
            TalariaLog.event("GenUI: IR root has no blocks array — no surface")
            return nil
        }

        let blocks = blockList.compactMap(block(from:))
        return GenUISurface(blocks: blocks).sanitized()
    }

    // MARK: - Node walkers

    private static func block(from any: Any) -> GenUIBlock? {
        guard let dict = any as? [String: Any] else {
            TalariaLog.event("GenUI: skipped non-object block entry")
            return nil
        }
        let kindName = string(dict, "kind")
        guard let kind = GenUIBlockKind(irName: kindName) else {
            TalariaLog.event("GenUI: skipped block of unknown kind '\(kindName)'")
            return nil
        }
        let children = (dict["children"] as? [Any] ?? []).compactMap(item(from:))
        return GenUIBlock(kind: kind, framed: bool(dict, "framed"), children: children)
    }

    private static func item(from any: Any) -> GenUIItem? {
        guard let dict = any as? [String: Any] else {
            TalariaLog.event("GenUI: skipped non-object item entry")
            return nil
        }
        let kindName = string(dict, "kind")
        guard let kind = GenUINodeKind(irName: kindName) else {
            TalariaLog.event("GenUI: skipped item of unknown kind '\(kindName)'")
            return nil
        }
        let children = (dict["children"] as? [Any] ?? []).compactMap(leaf(from:))
        return GenUIItem(
            kind: kind,
            children: children,
            text: string(dict, "text"),
            tone: tone(dict),
            size: size(dict),
            blinks: bool(dict, "blinks"),
            prompt: string(dict, "prompt")
        )
    }

    private static func leaf(from any: Any) -> GenUILeaf? {
        guard let dict = any as? [String: Any] else {
            TalariaLog.event("GenUI: skipped non-object leaf entry")
            return nil
        }
        let kindName = string(dict, "kind")
        guard let kind = GenUINodeKind(irName: kindName) else {
            TalariaLog.event("GenUI: skipped leaf of unknown kind '\(kindName)'")
            return nil
        }
        return GenUILeaf(
            kind: kind,
            text: string(dict, "text"),
            tone: tone(dict),
            size: size(dict),
            blinks: bool(dict, "blinks"),
            prompt: string(dict, "prompt")
        )
    }

    // MARK: - Field readers (wrong type or missing → the field's default)

    private static func string(_ dict: [String: Any], _ key: String) -> String {
        dict[key] as? String ?? ""
    }

    private static func bool(_ dict: [String: Any], _ key: String) -> Bool {
        // NSNumber bridging trap: JSONSerialization yields NSNumber for JSON
        // numbers, and `1 as? Bool` SUCCEEDS via bridging — so a wrong-typed
        // `"blinks": 1` would read as true instead of falling back. Accept
        // only genuine JSON booleans (CFBoolean), per the tolerance contract.
        guard let number = dict[key] as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }

    private static func tone(_ dict: [String: Any]) -> GenUITone {
        let name = string(dict, "tone")
        if name.isEmpty { return .standard }
        guard let tone = GenUITone(irName: name) else {
            TalariaLog.event("GenUI: unknown tone '\(name)' — using standard")
            return .standard
        }
        return tone
    }

    private static func size(_ dict: [String: Any]) -> GenUISize {
        let name = string(dict, "size")
        if name.isEmpty { return .medium }
        guard let size = GenUISize(irName: name) else {
            TalariaLog.event("GenUI: unknown size '\(name)' — using medium")
            return .medium
        }
        return size
    }
}

// MARK: - IR name mapping
//
// Exact case names, matched case-insensitively. Hand-written (not raw values)
// so the `@Generable` enums stay plain — the macro's verified surface.

extension GenUINodeKind {
    init?(irName: String) {
        switch irName.lowercased() {
        case "row": self = .row
        case "label": self = .label
        case "text": self = .text
        case "pip": self = .pip
        case "glowbutton": self = .glowButton
        case "ghostbutton": self = .ghostButton
        case "orb": self = .orb
        case "divider": self = .divider
        case "spacer": self = .spacer
        default: return nil
        }
    }
}

extension GenUIBlockKind {
    init?(irName: String) {
        switch irName.lowercased() {
        case "card": self = .card
        case "stack": self = .stack
        case "row": self = .row
        default: return nil
        }
    }
}

extension GenUITone {
    init?(irName: String) {
        switch irName.lowercased() {
        case "standard": self = .standard
        case "bright": self = .bright
        case "muted": self = .muted
        case "dim": self = .dim
        case "accent": self = .accent
        case "warning": self = .warning
        case "danger": self = .danger
        default: return nil
        }
    }
}

extension GenUISize {
    init?(irName: String) {
        switch irName.lowercased() {
        case "small": self = .small
        case "medium": self = .medium
        case "large": self = .large
        default: return nil
        }
    }
}

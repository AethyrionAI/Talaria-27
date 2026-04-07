import Foundation

/// A slash command available in the chat composer.
///
/// Commands fall into two categories:
/// - **Local**: Handled by the iOS app directly (new, undo, retry, etc.)
/// - **Pass-through**: Sent as a chat message to the Hermes agent, which
///   processes them natively (model, compress, background, skills, etc.)
///
/// The built-in list provides offline fallback. The full catalog (including
/// installed skills) is fetched at runtime from the relay via GET /v1/commands.
struct SlashCommand: Identifiable, Hashable {
    let name: String
    let description: String
    let category: String
    let acceptsArgument: Bool
    let isDestructive: Bool
    let isLocal: Bool
    let suggestedArgument: String?
    let showInAutocomplete: Bool

    init(
        name: String,
        description: String,
        category: String,
        acceptsArgument: Bool,
        isDestructive: Bool,
        isLocal: Bool,
        suggestedArgument: String? = nil,
        showInAutocomplete: Bool = true
    ) {
        self.name = name
        self.description = description
        self.category = category
        self.acceptsArgument = acceptsArgument
        self.isDestructive = isDestructive
        self.isLocal = isLocal
        self.suggestedArgument = suggestedArgument
        self.showInAutocomplete = showInAutocomplete
    }

    var id: String {
        suggestedArgument.map { "\(name)::\($0)" } ?? name
    }

    var displayTitle: String {
        if let suggestedArgument {
            return "/\(name) \(suggestedArgument)"
        }
        return "/\(name)"
    }

    var autocompleteQuery: String {
        if let suggestedArgument {
            return "\(name) \(suggestedArgument)".lowercased()
        }
        return name.lowercased()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SlashCommand, rhs: SlashCommand) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Built-in Fallback

extension SlashCommand {
    /// Offline fallback list — used when the relay catalog isn't available.
    /// The full catalog (with skills) is fetched dynamically via GET /v1/commands.
    static let allBuiltIn: [SlashCommand] = localCommands + gatewayCommands

    // Commands handled locally by the iOS app
    static let localCommands: [SlashCommand] = [
        SlashCommand(name: "new", description: "Start a new session", category: "Session", acceptsArgument: false, isDestructive: true, isLocal: true),
        SlashCommand(name: "clear", description: "Clear and start a new session", category: "Session", acceptsArgument: false, isDestructive: true, isLocal: true),
        SlashCommand(name: "undo", description: "Remove the last exchange", category: "Session", acceptsArgument: false, isDestructive: true, isLocal: true),
        SlashCommand(name: "retry", description: "Retry the last message", category: "Session", acceptsArgument: false, isDestructive: false, isLocal: true),
        SlashCommand(name: "save", description: "Save the conversation", category: "Session", acceptsArgument: false, isDestructive: false, isLocal: true),
        SlashCommand(name: "title", description: "Set session title", category: "Session", acceptsArgument: true, isDestructive: false, isLocal: true),
        SlashCommand(name: "history", description: "Show conversation history", category: "Session", acceptsArgument: false, isDestructive: false, isLocal: true),
    ]

    // Commands passed through to the Hermes agent — matches the gateway-available
    // surface from COMMAND_REGISTRY (cli_only=False commands)
    static let gatewayCommands: [SlashCommand] = [
        // Session
        SlashCommand(name: "compress", description: "Manually compress conversation context", category: "Session", acceptsArgument: false, isDestructive: false, isLocal: false),
        SlashCommand(name: "rollback", description: "List or restore filesystem checkpoints", category: "Session", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "stop", description: "Kill all running background processes", category: "Session", acceptsArgument: false, isDestructive: false, isLocal: false),
        SlashCommand(name: "background", description: "Run a prompt in the background", category: "Session", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "btw", description: "Ephemeral side question (no tools, not persisted)", category: "Session", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "queue", description: "Queue a prompt for the next turn", category: "Session", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "resume", description: "Resume a previously-named session", category: "Session", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "branch", description: "Branch the current session", category: "Session", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "approve", description: "Approve a pending dangerous command", category: "Session", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "deny", description: "Deny a pending dangerous command", category: "Session", acceptsArgument: false, isDestructive: false, isLocal: false),
        SlashCommand(name: "status", description: "Show session info", category: "Session", acceptsArgument: false, isDestructive: false, isLocal: false),
        SlashCommand(name: "sethome", description: "Set this chat as the home channel", category: "Session", acceptsArgument: false, isDestructive: false, isLocal: false),

        // Configuration
        SlashCommand(name: "model", description: "Switch model for this session", category: "Configuration", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "provider", description: "Show available providers", category: "Configuration", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "personality", description: "Set a predefined personality", category: "Configuration", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "yolo", description: "Toggle auto-approve mode", category: "Configuration", acceptsArgument: false, isDestructive: false, isLocal: false),
        SlashCommand(name: "reasoning", description: "Manage reasoning effort and display", category: "Configuration", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "voice", description: "Toggle voice mode", category: "Configuration", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "reload-mcp", description: "Reload MCP servers from config", category: "Tools & Skills", acceptsArgument: false, isDestructive: false, isLocal: false),

        // Info
        SlashCommand(name: "profile", description: "Show active profile and home directory", category: "Info", acceptsArgument: false, isDestructive: false, isLocal: false),
        SlashCommand(name: "commands", description: "Browse all commands and skills", category: "Info", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "help", description: "Show available commands", category: "Info", acceptsArgument: false, isDestructive: false, isLocal: false),
        SlashCommand(name: "usage", description: "Show token usage", category: "Info", acceptsArgument: false, isDestructive: false, isLocal: false),
        SlashCommand(name: "insights", description: "Show usage insights", category: "Info", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "update", description: "Update Hermes Agent", category: "Info", acceptsArgument: false, isDestructive: false, isLocal: false),
    ]

    /// Creates a pass-through command from a remote catalog entry.
    static func fromRemote(name: String, description: String, category: String, args: String?) -> SlashCommand {
        SlashCommand(
            name: name,
            description: description,
            category: category,
            acceptsArgument: args != nil,
            isDestructive: false,
            isLocal: false
        )
    }

    /// Creates a skill command from a remote catalog entry.
    static func fromSkill(name: String, description: String) -> SlashCommand {
        SlashCommand(
            name: name,
            description: description,
            category: "Skills",
            acceptsArgument: true,
            isDestructive: false,
            isLocal: false
        )
    }

    /// Creates a `/personality <name>` autocomplete suggestion.
    static func fromPersonality(name: String, description: String) -> SlashCommand {
        SlashCommand(
            name: "personality",
            description: description,
            category: "Personalities",
            acceptsArgument: true,
            isDestructive: false,
            isLocal: false,
            suggestedArgument: name
        )
    }

    /// Quick commands are valid Hermes slash commands, but Hermes docs state
    /// they are resolved at dispatch time and omitted from built-in autocomplete.
    static func fromQuickCommand(name: String, description: String) -> SlashCommand {
        SlashCommand(
            name: name,
            description: description,
            category: "Quick Commands",
            acceptsArgument: true,
            isDestructive: false,
            isLocal: false,
            showInAutocomplete: false
        )
    }
}

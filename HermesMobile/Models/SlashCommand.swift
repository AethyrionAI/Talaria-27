import Foundation

/// A slash command available in the chat composer.
///
/// Commands fall into two categories:
/// - **Local**: Handled by the iOS app directly (new, undo, retry, etc.)
/// - **Pass-through**: Sent as a chat message to the Hermes agent, which
///   processes them natively (model, compress, background, skills, etc.)
struct SlashCommand: Identifiable, Hashable {
    let name: String
    let description: String
    let acceptsArgument: Bool
    let isDestructive: Bool
    let isLocal: Bool  // true = handled by iOS app; false = sent to agent

    var id: String { name }
    var displayTitle: String { "/\(name)" }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: SlashCommand, rhs: SlashCommand) -> Bool {
        lhs.name == rhs.name
    }
}

// MARK: - Built-in Commands

extension SlashCommand {
    /// All built-in Hermes commands. Matches the full set available in
    /// Discord, Telegram, and the CLI — nothing is gatekept.
    static let allBuiltIn: [SlashCommand] = localCommands + agentCommands

    // MARK: Local (handled by iOS app)

    static let localCommands: [SlashCommand] = [
        SlashCommand(name: "new", description: "Start a new session", acceptsArgument: false, isDestructive: true, isLocal: true),
        SlashCommand(name: "reset", description: "Start a new session (alias for /new)", acceptsArgument: false, isDestructive: true, isLocal: true),
        SlashCommand(name: "clear", description: "Clear and start a new session", acceptsArgument: false, isDestructive: true, isLocal: true),
        SlashCommand(name: "undo", description: "Remove the last exchange", acceptsArgument: false, isDestructive: true, isLocal: true),
        SlashCommand(name: "retry", description: "Retry the last message", acceptsArgument: false, isDestructive: false, isLocal: true),
        SlashCommand(name: "save", description: "Save the conversation", acceptsArgument: false, isDestructive: false, isLocal: true),
        SlashCommand(name: "title", description: "Set session title", acceptsArgument: true, isDestructive: false, isLocal: true),
        SlashCommand(name: "history", description: "Show conversation history", acceptsArgument: false, isDestructive: false, isLocal: true),
    ]

    // MARK: Agent pass-through (sent as message text)

    static let agentCommands: [SlashCommand] = [
        // Session
        SlashCommand(name: "compress", description: "Compress conversation context", acceptsArgument: false, isDestructive: false, isLocal: false),
        SlashCommand(name: "rollback", description: "List or restore checkpoints", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "stop", description: "Kill background processes", acceptsArgument: false, isDestructive: false, isLocal: false),
        SlashCommand(name: "background", description: "Run a prompt in background", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "btw", description: "Side question (not persisted)", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "queue", description: "Queue a prompt for next turn", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "resume", description: "Resume a named session", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "branch", description: "Branch the current session", acceptsArgument: true, isDestructive: false, isLocal: false),

        // Configuration
        SlashCommand(name: "config", description: "Show current configuration", acceptsArgument: false, isDestructive: false, isLocal: false),
        SlashCommand(name: "model", description: "Switch model for this session", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "provider", description: "Show/switch providers", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "personality", description: "Set a personality", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "reasoning", description: "Set reasoning effort", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "yolo", description: "Toggle auto-approve mode", acceptsArgument: false, isDestructive: false, isLocal: false),

        // Info
        SlashCommand(name: "help", description: "Show available commands", acceptsArgument: false, isDestructive: false, isLocal: false),
        SlashCommand(name: "status", description: "Show session info", acceptsArgument: false, isDestructive: false, isLocal: false),
        SlashCommand(name: "usage", description: "Show token usage", acceptsArgument: false, isDestructive: false, isLocal: false),
        SlashCommand(name: "insights", description: "Show usage insights", acceptsArgument: true, isDestructive: false, isLocal: false),

        // Approval
        SlashCommand(name: "approve", description: "Approve a pending action", acceptsArgument: true, isDestructive: false, isLocal: false),
        SlashCommand(name: "deny", description: "Deny a pending action", acceptsArgument: true, isDestructive: false, isLocal: false),
    ]
}

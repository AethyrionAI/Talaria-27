import Foundation
import os

// Phase 3 slice 3A (#283): the runs-plane turn transport. Wire contract and
// probe evidence: design/PHASE3-RUNS-MIGRATION-PLAN-2026-08-07.md §2,
// planning/superpowers/research/251-phase3-gap/I-3a0-persistence-attachment-probe.md.
extension SessionsHermesClient {
    struct RunsTurnBody: Encodable {
        struct HistoryEntry: Encodable {
            let role: String
            let content: String
        }

        enum RunsTurnInput: Encodable {
            case text(String)
            /// Attachment turns: the 3A-0 probe proved a bare parts array 400s
            /// on /v1/runs ("No user message found in input") while the
            /// single-user-message wrap reaches the agent with the image intact.
            case userParts([ChatTurnBody.ContentPart])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let text):
                    try container.encode(text)
                case .userParts(let parts):
                    try container.encode([RunsInputMessage(parts: parts)])
                }
            }
        }

        private struct RunsInputMessage: Encodable {
            let parts: [ChatTurnBody.ContentPart]
            private enum CodingKeys: String, CodingKey { case role, content }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode("user", forKey: .role)
                try container.encode(parts, forKey: .content)
            }
        }

        let input: RunsTurnInput
        let sessionID: String
        let conversationHistory: [HistoryEntry]
        let provider: String?
        let model: String?

        private enum CodingKeys: String, CodingKey {
            case input, provider, model
            case sessionID = "session_id"
            case conversationHistory = "conversation_history"
        }

        // Nonisolated logger — same shape as `ChatTurnBody`'s: the enclosing
        // client is @MainActor, but this nested value type isn't.
        private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "SessionsHermesClient")

        static func make(
            message: String,
            attachments: [PendingAttachment],
            sessionID: String,
            history: [HistoryEntry],
            selection: ModelSelection?
        ) -> RunsTurnBody {
            let assembly = AttachmentInlining.assemble(message: message, attachments: attachments)

            // A raw (un-extracted) PDF or other binary has no wire shape; the
            // composer blocks send while one is staged (#8), so reaching this
            // means a non-UI path leaked one — log loudly, don't fail the turn.
            for fileName in assembly.notTransmittable {
                Self.logger.warning("Attachment \(fileName, privacy: .public) has no wire representation — not transmitted (#8)")
            }
            // Over-budget attachments already carry an in-band omission stub
            // so the agent (and the user, through it) sees the gap.
            for fileName in assembly.omittedForBudget {
                Self.logger.warning("Attachment \(fileName, privacy: .public) over aggregate body budget — omission stub sent instead")
            }

            let input: RunsTurnInput
            if assembly.parts.isEmpty {
                input = .text(message)
            } else {
                input = .userParts(assembly.parts.map { part in
                    switch part {
                    case .text(let text): ChatTurnBody.ContentPart.text(text)
                    case .imageDataURL(let dataURL): ChatTurnBody.ContentPart.imageURL(dataURL: dataURL)
                    }
                })
            }
            return RunsTurnBody(
                input: input,
                sessionID: sessionID,
                conversationHistory: history,
                provider: selection?.provider,
                model: selection?.modelID
            )
        }
    }
}

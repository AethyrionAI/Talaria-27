import Foundation

enum MessageSender: String, Codable, Hashable, Sendable {
    case user
    case hermes
    case system
    case voiceUser = "voice_user"
    case voiceHermes = "voice_hermes"
}

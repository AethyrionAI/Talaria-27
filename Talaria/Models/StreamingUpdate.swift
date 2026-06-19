import Foundation

enum StreamingUpdate: Sendable {
    case messageSent(jobID: UUID)
    case textDelta(String)
    case toolActivity(String)
    case finished(Message, TokenUsage?, CodeDiff?)
    case failed(String)
}

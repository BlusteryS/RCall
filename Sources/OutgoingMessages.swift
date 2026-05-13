import Foundation

private struct PingMessage: Encodable {
    let type = "ping"
}

private struct RtcReadyMessage: Encodable {
    let type = "rtc.ready"
    let epoch: Int
}

private struct AlarmSegmentMessage: Encodable {
    let type = "alarm.segment"
    let segment: AlarmSegment
}

private struct RtcAnswerMessage: Encodable {
    let type = "rtc.answer"
    let to: String
    let description: RtcSessionDescriptionPayload
}

private struct RtcCandidateMessage: Encodable {
    let type = "rtc.candidate"
    let to: String
    let candidate: RtcIceCandidatePayload
}

enum OutgoingRealtimeMessage {
    case ping
    case rtcReady(epoch: Int)
    case alarmSegment(AlarmSegment)
    case rtcAnswer(to: String, description: RtcSessionDescriptionPayload)
    case rtcCandidate(to: String, candidate: RtcIceCandidatePayload)

    func encode() throws -> Data {
        let encoder = JSONEncoder()

        switch self {
        case .ping:
            return try encoder.encode(PingMessage())
        case .rtcReady(let epoch):
            return try encoder.encode(RtcReadyMessage(epoch: epoch))
        case .alarmSegment(let segment):
            return try encoder.encode(AlarmSegmentMessage(segment: segment))
        case .rtcAnswer(let to, let description):
            return try encoder.encode(RtcAnswerMessage(to: to, description: description))
        case .rtcCandidate(let to, let candidate):
            return try encoder.encode(RtcCandidateMessage(to: to, candidate: candidate))
        }
    }
}

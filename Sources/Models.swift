import Foundation

struct PinResponse: Decodable {
    let pinTicket: String
}

struct SessionResponse: Decodable {
    let role: String
    let token: String
}

struct Attachment: Codable {
    let id: String
    let fileName: String
    let mimeType: String
    let size: Int
    let createdAt: String
    let source: String
    let revision: Int
}

struct ChatMessage: Codable {
    let id: String
    let role: String
    let text: String?
    let attachment: Attachment?
    let createdAt: String
}

struct RtcIceServer: Codable {
    let urls: [String]
    let username: String
    let credential: String
}

struct RtcConfig: Codable {
    let iceServers: [RtcIceServer]
    let iceTransportPolicy: String
}

struct BootstrapResponse: Decodable {
    let role: String
    let attachments: [Attachment]
    let messages: [ChatMessage]
    let rtc: RtcConfig
    let serverTime: String
}

struct RtcPeer: Codable, Equatable {
    let id: String
    let role: String
}

struct AlarmSegment: Codable {
    let id: String
    let sequence: Int
    let startedAt: Double
    let endedAt: Double
}

struct RtcSessionDescriptionPayload: Codable {
    let type: String
    let sdp: String
}

struct RtcIceCandidatePayload: Codable {
    let candidate: String
    let sdpMid: String?
    let sdpMLineIndex: Int32?
}

enum RealtimeMessage {
    case ready(ReadyPayload)
    case pong
    case peerJoined(RtcPeer)
    case peerLeft(RtcPeer)
    case offer(from: String, description: RtcSessionDescriptionPayload)
    case answer(from: String, description: RtcSessionDescriptionPayload)
    case candidate(from: String, candidate: RtcIceCandidatePayload)
    case ignored
}

struct ReadyPayload: Decodable {
    let clientId: String
    let role: String
    let attachments: [Attachment]
    let messages: [ChatMessage]
    let rtc: RtcConfig
    let serverTime: String
}

private struct MessageType: Decodable {
    let type: String
}

private struct ReadyMessagePayload: Decodable {
    let type: String
    let clientId: String
    let role: String
    let attachments: [Attachment]
    let messages: [ChatMessage]
    let rtc: RtcConfig
    let serverTime: String
}

private struct PeerMessagePayload: Decodable {
    let type: String
    let peer: RtcPeer
}

private struct RtcDescriptionMessagePayload: Decodable {
    let type: String
    let from: String
    let description: RtcSessionDescriptionPayload
}

private struct RtcCandidateMessagePayload: Decodable {
    let type: String
    let from: String
    let candidate: RtcIceCandidatePayload
}

extension RealtimeMessage {
    static func decode(from data: Data) throws -> RealtimeMessage {
        let decoder = JSONDecoder()
        let typed = try decoder.decode(MessageType.self, from: data)

        switch typed.type {
        case "ready":
            let payload = try decoder.decode(ReadyMessagePayload.self, from: data)
            return .ready(
                ReadyPayload(
                    clientId: payload.clientId,
                    role: payload.role,
                    attachments: payload.attachments,
                    messages: payload.messages,
                    rtc: payload.rtc,
                    serverTime: payload.serverTime
                )
            )
        case "pong":
            return .pong
        case "rtc.peer.joined":
            return .peerJoined(try decoder.decode(PeerMessagePayload.self, from: data).peer)
        case "rtc.peer.left":
            return .peerLeft(try decoder.decode(PeerMessagePayload.self, from: data).peer)
        case "rtc.offer":
            let payload = try decoder.decode(RtcDescriptionMessagePayload.self, from: data)
            return .offer(from: payload.from, description: payload.description)
        case "rtc.answer":
            let payload = try decoder.decode(RtcDescriptionMessagePayload.self, from: data)
            return .answer(from: payload.from, description: payload.description)
        case "rtc.candidate":
            let payload = try decoder.decode(RtcCandidateMessagePayload.self, from: data)
            return .candidate(from: payload.from, candidate: payload.candidate)
        default:
            return .ignored
        }
    }
}

struct UploadAttachmentResponse: Decodable {
    let attachment: Attachment
}

struct SendChatResponse: Decodable {
    let message: ChatMessage
}

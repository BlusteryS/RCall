import AVFoundation
import Foundation
import WebRTC

protocol WebRTCClientDelegate: AnyObject {
    func webRTCClientNeedsSend(_ message: OutgoingRealtimeMessage)
    func webRTCClientDidChangeConnection(connected: Bool)
}

final class WebRTCClient: NSObject {
    weak var delegate: WebRTCClientDelegate?

    private let factory: RTCPeerConnectionFactory
    private var peers: [String: PeerRecord] = [:]
    private var rtcConfig: RtcConfig?
    private var rtcEpoch = 0

    override init() {
        RTCInitializeSSL()
        RTCSetMinDebugLogLevel(.warning)
        factory = RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
        super.init()
        configureAudioSession()
    }

    func configure(rtc: RtcConfig) {
        rtcConfig = rtc
    }

    func markReady(forceRenegotiation: Bool = false) {
        if forceRenegotiation {
            rtcEpoch += 1
        }

        delegate?.webRTCClientNeedsSend(.rtcReady(epoch: rtcEpoch))
    }

    func handle(_ message: RealtimeMessage) {
        switch message {
        case .ready(let payload):
            configure(rtc: payload.rtc)
            markReady()
        case .peerJoined(let peer):
            guard peer.role == "home" else {
                return
            }
            markReady()
        case .peerLeft(let peer):
            schedulePeerGraceClose(peerId: peer.id)
        case .offer(let from, let description):
            Task { await handleOffer(from: from, description: description) }
        case .candidate(let from, let candidate):
            handleCandidate(from: from, payload: candidate)
        case .pong, .answer, .ignored:
            break
        }
    }

    func repair() {
        var needsRenegotiation = false
        for record in peers.values where !record.isHealthy {
            close(peerId: record.peerId)
            needsRenegotiation = true
        }
        markReady(forceRenegotiation: needsRenegotiation)
    }

    func forceNetworkRepair() {
        let hadPeers = !peers.isEmpty
        for peerId in peers.keys {
            close(peerId: peerId)
        }
        markReady(forceRenegotiation: hadPeers)
    }

    func closeAll() {
        for peerId in peers.keys {
            close(peerId: peerId)
        }
    }

    private func handleOffer(from: String, description: RtcSessionDescriptionPayload) async {
        guard description.type == "offer" else {
            return
        }

        let record = createPeer(peerId: from, replace: false)
        let remote = RTCSessionDescription(type: .offer, sdp: description.sdp)

        do {
            try await record.connection.setRemoteDescriptionAsync(remote)
            flushPendingCandidates(record)
            let answer = try await record.connection.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
            let tuned = RTCSessionDescription(type: .answer, sdp: tuneOpus(answer.sdp))
            try await record.connection.setLocalDescriptionAsync(tuned)
            delegate?.webRTCClientNeedsSend(
                .rtcAnswer(
                    to: from,
                    description: RtcSessionDescriptionPayload(type: "answer", sdp: tuned.sdp)
                )
            )
        } catch {
            close(peerId: from)
            markReady()
        }
    }

    private func handleCandidate(from: String, payload: RtcIceCandidatePayload) {
        guard let record = peers[from] else {
            return
        }

        let candidate = RTCIceCandidate(
            sdp: payload.candidate,
            sdpMLineIndex: payload.sdpMLineIndex ?? 0,
            sdpMid: payload.sdpMid
        )

        guard record.connection.remoteDescription != nil else {
            record.pendingCandidates.append(candidate)
            return
        }

        record.connection.add(candidate)
    }

    private func createPeer(peerId: String, replace: Bool) -> PeerRecord {
        if let existing = peers[peerId], !replace {
            existing.cancelGraceClose()
            existing.cancelRepair()
            return existing
        }

        close(peerId: peerId)

        let configuration = makeConfiguration()
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let connection = factory.peerConnection(with: configuration, constraints: constraints, delegate: nil)!
        let record = PeerRecord(peerId: peerId, connection: connection)
        peers[peerId] = record
        connection.delegate = self
        return record
    }

    private func makeConfiguration() -> RTCConfiguration {
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.bundlePolicy = .maxBundle
        configuration.rtcpMuxPolicy = .require
        configuration.iceTransportPolicy = .relay
        configuration.continualGatheringPolicy = .gatherContinually
        configuration.audioJitterBufferMaxPackets = AppConfig.rtcJitterBufferPackets
        configuration.audioJitterBufferFastAccelerate = false
        configuration.iceServers = rtcConfig?.iceServers.map {
            RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential)
        } ?? []
        return configuration
    }

    private func flushPendingCandidates(_ record: PeerRecord) {
        let candidates = record.pendingCandidates
        record.pendingCandidates.removeAll(keepingCapacity: true)
        for candidate in candidates {
            record.connection.add(candidate)
        }
    }

    private func schedulePeerGraceClose(peerId: String) {
        guard let record = peers[peerId] else {
            return
        }

        record.cancelGraceClose()
        record.graceClose = DispatchWorkItem { [weak self] in
            guard let self, let current = self.peers[peerId], !current.isHealthy else {
                return
            }
            self.close(peerId: peerId)
            self.markReady()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: record.graceClose!)
    }

    private func schedulePeerRepair(_ peerConnection: RTCPeerConnection) {
        guard let record = peers.values.first(where: { $0.connection === peerConnection }) else {
            return
        }

        if record.repairWork != nil {
            return
        }

        let work = DispatchWorkItem { [weak self, weak record] in
            guard let self, let record, self.peers[record.peerId] === record else {
                return
            }

            record.repairWork = nil
            guard !record.isHealthy else {
                return
            }

            self.close(peerId: record.peerId)
            self.markReady(forceRenegotiation: true)
        }
        record.repairWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func close(peerId: String) {
        guard let record = peers.removeValue(forKey: peerId) else {
            return
        }

        record.cancelGraceClose()
        record.cancelRepair()
        record.connection.close()
        notifyConnectionStatus()
    }

    private func notifyConnectionStatus() {
        delegate?.webRTCClientDidChangeConnection(connected: peers.values.contains { $0.isHealthy })
    }

    private func configureAudioSession() {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }

        do {
            try session.setCategory(.playback, with: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setMode(.spokenAudio)
            try session.setPreferredSampleRate(48_000)
            try session.setActive(true)
        } catch {
            return
        }
    }

    private func tuneOpus(_ sdp: String) -> String {
        let lines = sdp.components(separatedBy: "\r\n")
        guard let opusLine = lines.first(where: { $0.range(of: #"^a=rtpmap:(\d+) opus/48000/2$"#, options: .regularExpression) != nil }),
              let payload = opusLine.split(separator: " ").first?.split(separator: ":").last else {
            return sdp
        }

        var output: [String] = []
        var wroteFmtp = false
        var wrotePtime = false
        var wroteMaxPtime = false

        for line in lines {
            if line.hasPrefix("a=fmtp:\(payload) ") {
                output.append("a=fmtp:\(payload) minptime=10;useinbandfec=1;usedtx=0;stereo=0;sprop-stereo=0;maxaveragebitrate=\(AppConfig.opusMaxAverageBitrate)")
                wroteFmtp = true
                continue
            }

            if line.hasPrefix("a=ptime:") {
                output.append("a=ptime:20")
                wrotePtime = true
                continue
            }

            if line.hasPrefix("a=maxptime:") {
                output.append("a=maxptime:60")
                wroteMaxPtime = true
                continue
            }

            output.append(line)
        }

        if !wroteFmtp {
            output.insert("a=fmtp:\(payload) minptime=10;useinbandfec=1;usedtx=0;stereo=0;sprop-stereo=0;maxaveragebitrate=\(AppConfig.opusMaxAverageBitrate)", afterFirst: { $0 == opusLine })
        }
        if !wrotePtime {
            output.insert("a=ptime:20", afterFirst: { $0 == opusLine })
        }
        if !wroteMaxPtime {
            output.insert("a=maxptime:60", afterFirst: { $0 == "a=ptime:20" })
        }

        return output.joined(separator: "\r\n")
    }
}

private final class PeerRecord {
    let peerId: String
    let connection: RTCPeerConnection
    var pendingCandidates: [RTCIceCandidate] = []
    var graceClose: DispatchWorkItem?
    var repairWork: DispatchWorkItem?

    init(peerId: String, connection: RTCPeerConnection) {
        self.peerId = peerId
        self.connection = connection
    }

    var isHealthy: Bool {
        connection.connectionState == .connected ||
            connection.iceConnectionState == .connected ||
            connection.iceConnectionState == .completed
    }

    func cancelGraceClose() {
        graceClose?.cancel()
        graceClose = nil
    }

    func cancelRepair() {
        repairWork?.cancel()
        repairWork = nil
    }
}

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        notifyConnectionStatus()
        if newState == .connected || newState == .completed {
            peers.values.first(where: { $0.connection === peerConnection })?.cancelRepair()
        }
        if newState == .failed || newState == .disconnected {
            schedulePeerRepair(peerConnection)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        notifyConnectionStatus()
        if newState == .connected {
            peers.values.first(where: { $0.connection === peerConnection })?.cancelRepair()
        }
        if newState == .failed || newState == .disconnected {
            schedulePeerRepair(peerConnection)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let record = peers.values.first(where: { $0.connection === peerConnection }) else {
            return
        }

        delegate?.webRTCClientNeedsSend(
            .rtcCandidate(
                to: record.peerId,
                candidate: RtcIceCandidatePayload(
                    candidate: candidate.sdp,
                    sdpMid: candidate.sdpMid,
                    sdpMLineIndex: candidate.sdpMLineIndex
                )
            )
        )
    }
}

private extension RTCPeerConnection {
    func setRemoteDescriptionAsync(_ description: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func setLocalDescriptionAsync(_ description: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func answer(for constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            answer(for: constraints) { description, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: NSError(domain: "RCallWebRTC", code: 1))
                }
            }
        }
    }
}

private extension Array where Element == String {
    mutating func insert(_ value: String, afterFirst predicate: (String) -> Bool) {
        guard let index = firstIndex(where: predicate) else {
            append(value)
            return
        }

        insert(value, at: index + 1)
    }
}

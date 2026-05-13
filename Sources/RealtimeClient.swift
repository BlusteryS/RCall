import Foundation
import Network

protocol RealtimeClientDelegate: AnyObject {
    func realtimeClientDidConnect(_ client: RealtimeClient)
    func realtimeClient(_ client: RealtimeClient, didReceive message: RealtimeMessage)
    func realtimeClientDidDisconnect(_ client: RealtimeClient)
    func realtimeClientNetworkPathDidChange(_ client: RealtimeClient)
}

final class RealtimeClient {
    weak var delegate: RealtimeClientDelegate?

    private let url: URL
    private let queue = DispatchQueue(label: "rcall.realtime")
    private let queueKey = DispatchSpecificKey<Void>()
    private let monitor = NWPathMonitor()
    private var socket: URLSessionWebSocketTask?
    private var reconnectWork: DispatchWorkItem?
    private var pingTimer: DispatchSourceTimer?
    private var pongTimer: DispatchSourceTimer?
    private var outboundQueue: [OutgoingRealtimeMessage] = []
    private var reconnectAttempt = 0
    private var manuallyStopped = false
    private var connected = false
    private var lastPathSignature: String?

    init(url: URL) {
        self.url = url
        queue.setSpecific(key: queueKey, value: ())
        monitor.pathUpdateHandler = { [weak self] path in
            self?.queue.async {
                guard let self else {
                    return
                }

                let signature = Self.pathSignature(path)
                let changed = self.lastPathSignature != nil && self.lastPathSignature != signature
                self.lastPathSignature = signature

                guard path.status == .satisfied else {
                    return
                }

                self.connectIfNeeded()
                if changed {
                    DispatchQueue.main.async {
                        self.delegate?.realtimeClientNetworkPathDidChange(self)
                    }
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        stop()
        monitor.cancel()
    }

    func start() {
        queue.async {
            self.manuallyStopped = false
            self.connectIfNeeded()
        }
    }

    func stop() {
        queue.async {
            self.manuallyStopped = true
            self.connected = false
            self.reconnectWork?.cancel()
            self.reconnectWork = nil
            self.stopTimers()
            self.socket?.cancel(with: .goingAway, reason: nil)
            self.socket = nil
        }
    }

    @discardableResult
    func send(_ message: OutgoingRealtimeMessage) -> Bool {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return sendLocked(message)
        }

        return queue.sync { sendLocked(message) }
    }

    private func sendLocked(_ message: OutgoingRealtimeMessage) -> Bool {
        guard connected, let socket else {
            enqueue(message)
            return false
        }

        sendNow(message, socket: socket)
        return true
    }

    private func connectIfNeeded() {
        guard !manuallyStopped, socket == nil else {
            return
        }

        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        connected = true
        reconnectAttempt = 0
        startTimers()
        receiveLoop(task)

        DispatchQueue.main.async {
            self.delegate?.realtimeClientDidConnect(self)
        }

        flushQueue()
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else {
                return
            }

            self.queue.async {
                guard self.socket === task else {
                    return
                }

                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receiveLoop(task)
                case .failure:
                    self.handleDisconnect()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?

        switch message {
        case .data(let value):
            data = value
        case .string(let value):
            data = value.data(using: .utf8)
        @unknown default:
            data = nil
        }

        guard let data, let decoded = try? RealtimeMessage.decode(from: data) else {
            return
        }

        if case .pong = decoded {
            resetPongTimeout()
        }

        DispatchQueue.main.async {
            self.delegate?.realtimeClient(self, didReceive: decoded)
        }
    }

    private func sendNow(_ message: OutgoingRealtimeMessage, socket: URLSessionWebSocketTask) {
        guard let data = try? message.encode(), let text = String(data: data, encoding: .utf8) else {
            return
        }

        socket.send(.string(text)) { [weak self] error in
            guard let self, error != nil else {
                return
            }

            self.queue.async {
                self.enqueue(message)
                self.handleDisconnect()
            }
        }
    }

    private func enqueue(_ message: OutgoingRealtimeMessage) {
        outboundQueue.append(message)
        if outboundQueue.count > AppConfig.signalQueueLimit {
            outboundQueue.removeFirst(outboundQueue.count - AppConfig.signalQueueLimit)
        }
    }

    private func flushQueue() {
        guard connected, let socket else {
            return
        }

        let queued = outboundQueue
        outboundQueue.removeAll(keepingCapacity: true)
        for message in queued {
            sendNow(message, socket: socket)
        }
    }

    private func handleDisconnect() {
        guard socket != nil else {
            return
        }

        connected = false
        stopTimers()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil

        DispatchQueue.main.async {
            self.delegate?.realtimeClientDidDisconnect(self)
        }

        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !manuallyStopped, monitor.currentPath.status == .satisfied else {
            return
        }

        reconnectWork?.cancel()
        reconnectAttempt += 1
        let delay = min(pow(1.7, Double(reconnectAttempt - 1)), AppConfig.maxReconnectDelay)
        let work = DispatchWorkItem { [weak self] in
            self?.connectIfNeeded()
        }
        reconnectWork = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startTimers() {
        stopTimers()

        let ping = DispatchSource.makeTimerSource(queue: queue)
        ping.schedule(deadline: .now() + AppConfig.pingInterval, repeating: AppConfig.pingInterval)
        ping.setEventHandler { [weak self] in
            guard let self, self.connected else {
                return
            }

            _ = self.send(.ping)
            self.startPongTimeout()
        }
        ping.resume()
        pingTimer = ping
    }

    private func stopTimers() {
        pingTimer?.cancel()
        pingTimer = nil
        pongTimer?.cancel()
        pongTimer = nil
    }

    private func startPongTimeout() {
        pongTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + AppConfig.pongTimeout)
        timer.setEventHandler { [weak self] in
            self?.handleDisconnect()
        }
        timer.resume()
        pongTimer = timer
    }

    private func resetPongTimeout() {
        pongTimer?.cancel()
        pongTimer = nil
    }

    private static func pathSignature(_ path: NWPath) -> String {
        let interfaces = NWInterface.InterfaceType.allCases
            .filter { path.usesInterfaceType($0) }
            .map(\.signatureName)
            .joined(separator: ",")
        return "\(path.status.signatureName):\(path.isExpensive):\(path.isConstrained):\(interfaces)"
    }
}

private extension NWPath.Status {
    var signatureName: String {
        switch self {
        case .satisfied:
            return "satisfied"
        case .unsatisfied:
            return "unsatisfied"
        case .requiresConnection:
            return "requiresConnection"
        @unknown default:
            return "unknown"
        }
    }
}

private extension NWInterface.InterfaceType {
    static let allCases: [NWInterface.InterfaceType] = [
        .wifi,
        .cellular,
        .wiredEthernet,
        .loopback,
        .other,
    ]

    var signatureName: String {
        switch self {
        case .wifi:
            return "wifi"
        case .cellular:
            return "cellular"
        case .wiredEthernet:
            return "ethernet"
        case .loopback:
            return "loopback"
        case .other:
            return "other"
        @unknown default:
            return "unknown"
        }
    }
}

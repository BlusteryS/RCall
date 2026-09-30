import AVFoundation
import Foundation
import WebRTC

final class AudioOutputPolicy {
    static let shared = AudioOutputPolicy()
    private let lock = NSLock()
    private var tracks: [RTCAudioTrack] = []
    private var interrupted = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.refresh()
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] event in
            guard let self, let raw = event.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            self.lock.lock()
            self.interrupted = raw == AVAudioSession.InterruptionType.began.rawValue
            self.updateLocked()
            self.lock.unlock()
        })
    }

    func register(_ track: RTCAudioTrack) {
        track.source.volume = 0
        lock.lock()
        if !tracks.contains(where: { $0 === track }) { tracks.append(track) }
        updateLocked()
        lock.unlock()
    }

    func unregister(_ track: RTCAudioTrack) {
        lock.lock()
        track.source.volume = 0
        tracks.removeAll { $0 === track }
        lock.unlock()
    }

    func refresh() {
        lock.lock()
        updateLocked()
        lock.unlock()
    }

    private func updateLocked() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let bluetoothPorts: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
        let allowed = !interrupted && !outputs.isEmpty && outputs.allSatisfy { bluetoothPorts.contains($0.portType) }
        for track in tracks { track.source.volume = allowed ? 1 : 0 }
    }
}

final class BackgroundAudioKeeper {
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var configured = false
    private var running = false
    private var wanted = false
    private var interrupted = false
    private var retry: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] event in
            guard let self, let raw = event.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            self.interrupted = raw == AVAudioSession.InterruptionType.began.rawValue
            self.resetPlayback()
            if !self.interrupted && self.wanted { self.start() }
        })
        for name in [AVAudioSession.routeChangeNotification, AVAudioSession.mediaServicesWereResetNotification, Notification.Name.AVAudioEngineConfigurationChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] event in
                guard let self, self.wanted else { return }
                if name == Notification.Name.AVAudioEngineConfigurationChange {
                    guard event.object as? AVAudioEngine === self.engine, !self.engine.isRunning else { return }
                }
                self.resetPlayback()
                self.engine = AVAudioEngine()
                self.player = AVAudioPlayerNode()
                self.configured = false
                self.scheduleRetry()
            })
        }
    }

    deinit {
        retry?.cancel()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func start() {
        wanted = true
        guard !interrupted, !(running && engine.isRunning && player.isPlaying) else {
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
            try session.setPreferredSampleRate(48_000)
            try session.setActive(true)

            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
            buffer.frameLength = buffer.frameCapacity

            if !configured {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, fromBus: 0, toBus: 0, format: format)
                configured = true
            }
            engine.prepare()
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.volume = 0
            player.play()
            running = true
            retry?.cancel()
            retry = nil
            AudioOutputPolicy.shared.refresh()
        } catch {
            resetPlayback()
            scheduleRetry()
        }
    }

    func stop() {
        wanted = false
        resetPlayback()
    }

    private func resetPlayback() {
        retry?.cancel()
        retry = nil
        player.stop()
        engine.stop()
        running = false
    }

    private func scheduleRetry() {
        guard wanted, !interrupted, retry == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.retry = nil
            self?.start()
        }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
}

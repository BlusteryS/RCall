import AVFoundation
import Foundation

final class BackgroundAudioKeeper {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var configured = false
    private var running = false

    func start() {
        guard !running else {
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setPreferredSampleRate(48_000)
            try session.setActive(true)

            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
            buffer.frameLength = buffer.frameCapacity

            if !configured {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                configured = true
            }
            engine.prepare()
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.volume = 0.001
            player.play()
            running = true
        } catch {
            stop()
        }
    }

    func stop() {
        player.stop()
        engine.stop()
        running = false
    }
}

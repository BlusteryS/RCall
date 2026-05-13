import Foundation
import UIKit

enum AppConfig {
    static let apiBaseURL = RuntimeConfig.load().apiBaseURL
    static let role = "campus"
    static let chatTextLimit = 300
    static let pingInterval: TimeInterval = 7
    static let pongTimeout: TimeInterval = 30
    static let maxReconnectDelay: TimeInterval = 5
    static let signalQueueLimit = 200
    static let rtcJitterBufferPackets: Int32 = 50
    static let opusMaxAverageBitrate = 64_000
    static let cameraBurstCount = 3
    static let cameraBurstInterval: TimeInterval = 0.5
}

private struct RuntimeConfig {
    let apiBaseURL: URL

    static func load() -> RuntimeConfig {
        guard let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
              let values = NSDictionary(contentsOfFile: path),
              let rawURL = values["APIBaseURL"] as? String,
              let url = URL(string: rawURL),
              url.scheme == "https",
              url.host != nil else {
            preconditionFailure("Invalid runtime configuration")
        }

        return RuntimeConfig(apiBaseURL: url)
    }
}

enum AppColors {
    static let background = UIColor(red: 0.95, green: 0.93, blue: 0.86, alpha: 1)
    static let ink = UIColor(red: 0.10, green: 0.11, blue: 0.10, alpha: 1)
    static let mutedInk = UIColor(red: 0.36, green: 0.36, blue: 0.32, alpha: 1)
    static let panel = UIColor(red: 1.00, green: 0.98, blue: 0.91, alpha: 1)
    static let camera = UIColor(red: 0.05, green: 0.39, blue: 0.32, alpha: 1)
    static let signal = UIColor(red: 0.83, green: 0.19, blue: 0.13, alpha: 1)
    static let chat = UIColor(red: 0.15, green: 0.22, blue: 0.30, alpha: 1)
}

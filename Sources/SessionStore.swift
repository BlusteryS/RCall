import CoreGraphics
import Foundation

final class SessionStore {
    static let shared = SessionStore()

    private enum Keys {
        static let token = "rcall.session.token"
        static let deviceId = "rcall.device.id"
        static let cameraZoom = "rcall.camera.zoom"
    }

    private let defaults = UserDefaults.standard

    var token: String? {
        get { defaults.string(forKey: Keys.token) }
        set { defaults.set(newValue, forKey: Keys.token) }
    }

    var deviceId: String {
        if let stored = defaults.string(forKey: Keys.deviceId), !stored.isEmpty {
            return stored
        }

        let next = UUID().uuidString.lowercased()
        defaults.set(next, forKey: Keys.deviceId)
        return next
    }

    var cameraZoom: CGFloat {
        get {
            let value = defaults.double(forKey: Keys.cameraZoom)
            return value >= 1 ? CGFloat(value) : 1
        }
        set {
            defaults.set(Double(max(1, newValue)), forKey: Keys.cameraZoom)
        }
    }

    func resetSession() {
        defaults.removeObject(forKey: Keys.token)
    }
}

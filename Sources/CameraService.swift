import AVFoundation
import UIKit

protocol CameraServiceDelegate: AnyObject {
    func cameraService(_ service: CameraService, didCaptureJPEG data: Data)
    func cameraService(_ service: CameraService, didFail error: Error)
}

final class CameraService: NSObject {
    weak var delegate: CameraServiceDelegate?

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "rcall.camera.session")
    private let output = AVCapturePhotoOutput()
    private let store: SessionStore
    private var device: AVCaptureDevice?
    private var startZoom: CGFloat = 1
    private var configured = false
    private var configuring = false
    private var wantsRunning = false

    init(store: SessionStore = .shared) {
        self.store = store
        super.init()
    }

    func prepare() {
        ensureConfigured(startWhenReady: false)
    }

    func start() {
        ensureConfigured(startWhenReady: true)
    }

    func stop() {
        sessionQueue.async {
            self.wantsRunning = false
            guard self.session.isRunning else {
                return
            }
            self.session.stopRunning()
        }
    }

    func captureBurst(count: Int, interval: TimeInterval) {
        let safeCount = max(1, count)
        let safeInterval = max(0.1, interval)

        for index in 0..<safeCount {
            let delay = DispatchTimeInterval.milliseconds(Int(safeInterval * 1_000) * index)
            sessionQueue.asyncAfter(deadline: .now() + delay) {
                self.captureLocked()
            }
        }
    }

    private func ensureConfigured(startWhenReady: Bool) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async {
                self.configureLocked(startWhenReady: startWhenReady)
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else {
                    return
                }
                self.sessionQueue.async {
                    if granted {
                        self.configureLocked(startWhenReady: startWhenReady)
                    } else {
                        self.fail(CameraError.permissionDenied)
                    }
                }
            }
        case .denied, .restricted:
            fail(CameraError.permissionDenied)
        @unknown default:
            fail(CameraError.permissionDenied)
        }
    }

    private func configureLocked(startWhenReady: Bool) {
        wantsRunning = wantsRunning || startWhenReady

        if configured {
            startLockedIfNeeded()
            return
        }

        guard !configuring else {
            return
        }

        configuring = true
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        do {
            let device = try selectBackCamera()
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(output) else {
                throw CameraError.configuration
            }

            session.addInput(input)
            session.addOutput(output)
            configurePhotoDimensions(for: device)
            output.maxPhotoQualityPrioritization = .quality
            self.device = device
            disableAutoMacroIfAvailable(device)
            applyZoom(store.cameraZoom)
            configured = true
            configuring = false
            session.commitConfiguration()
            startLockedIfNeeded()
        } catch {
            configuring = false
            session.commitConfiguration()
            fail(error)
        }
    }

    private func startLockedIfNeeded() {
        guard wantsRunning, !session.isRunning else {
            return
        }
        session.startRunning()
    }

    private func captureLocked() {
        guard configured, session.isRunning else {
            fail(CameraError.capture)
            return
        }

        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        settings.photoQualityPrioritization = .quality
        output.capturePhoto(with: settings, delegate: self)
    }

    func beginZoom() {
        sessionQueue.async {
            self.startZoom = self.device?.videoZoomFactor ?? 1
        }
    }

    func zoom(scale: CGFloat) {
        sessionQueue.async {
            self.applyZoom(self.startZoom * scale)
        }
    }

    private func selectBackCamera() throws -> AVCaptureDevice {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .back
        )

        guard let device = discovery.devices.first else {
            throw CameraError.noBackCamera
        }

        return device
    }

    private func applyZoom(_ value: CGFloat) {
        guard let device else {
            return
        }

        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 15)
        let zoom = min(max(1, value), maxZoom)

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.videoZoomFactor = zoom
            store.cameraZoom = zoom
        } catch {
            return
        }
    }

    private func configurePhotoDimensions(for device: AVCaptureDevice) {
        let dimensions = device.activeFormat.supportedMaxPhotoDimensions
        guard let largest = dimensions.max(by: { left, right in
            Int64(left.width) * Int64(left.height) < Int64(right.width) * Int64(right.height)
        }) else {
            return
        }

        output.maxPhotoDimensions = largest
    }

    private func disableAutoMacroIfAvailable(_ device: AVCaptureDevice) {
        let selector = NSSelectorFromString("setAutoMacroEnabled:")
        guard device.responds(to: selector) else {
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.setValue(false, forKey: "autoMacroEnabled")
        } catch {
            return
        }
    }

    private func fail(_ error: Error) {
        DispatchQueue.main.async {
            self.delegate?.cameraService(self, didFail: error)
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            DispatchQueue.main.async {
                self.delegate?.cameraService(self, didFail: error)
            }
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                self.delegate?.cameraService(self, didFail: CameraError.capture)
            }
            return
        }

        DispatchQueue.main.async {
            self.delegate?.cameraService(self, didCaptureJPEG: data)
        }
    }
}

enum CameraError: Error {
    case noBackCamera
    case configuration
    case capture
    case permissionDenied
}

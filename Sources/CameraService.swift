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
    private var pendingBurstCaptures = 0
    private var burstInterval: TimeInterval = AppConfig.cameraSeriesInterval
    private var burstGeneration = 0

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
            self.pendingBurstCaptures = 0
            self.burstGeneration += 1
            guard self.session.isRunning else {
                return
            }
            self.session.stopRunning()
        }
    }

    func capturePhotos(count: Int, interval: TimeInterval) {
        let safeCount = max(1, count)
        let safeInterval = safeCount > 1 ? max(0.1, interval) : 0

        sessionQueue.async {
            guard self.configured, self.session.isRunning else {
                self.fail(CameraError.capture)
                return
            }

            self.pendingBurstCaptures = safeCount - 1
            self.burstInterval = safeInterval
            self.burstGeneration += 1
            self.captureLocked(generation: self.burstGeneration)
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
            preparePhotoOutputLocked()
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

    private func captureLocked(generation: Int? = nil) {
        if let generation, generation != burstGeneration {
            return
        }

        guard configured, session.isRunning else {
            if generation == nil {
                fail(CameraError.capture)
            }
            return
        }

        output.capturePhoto(with: makePhotoSettings(), delegate: self)
    }

    private func scheduleNextBurstCaptureIfNeeded() {
        guard pendingBurstCaptures > 0, session.isRunning else {
            pendingBurstCaptures = 0
            return
        }

        pendingBurstCaptures -= 1
        let generation = burstGeneration
        let delay = DispatchTimeInterval.milliseconds(Int(burstInterval * 1_000))
        sessionQueue.asyncAfter(deadline: .now() + delay) {
            self.captureLocked(generation: generation)
        }
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

    private func makePhotoSettings() -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        settings.photoQualityPrioritization = .quality
        return settings
    }

    private func preparePhotoOutputLocked() {
        output.setPreparedPhotoSettingsArray([makePhotoSettings()], completionHandler: nil)
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
            sessionQueue.async {
                self.pendingBurstCaptures = 0
                self.burstGeneration += 1
            }
            DispatchQueue.main.async {
                self.delegate?.cameraService(self, didFail: error)
            }
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            sessionQueue.async {
                self.pendingBurstCaptures = 0
                self.burstGeneration += 1
            }
            DispatchQueue.main.async {
                self.delegate?.cameraService(self, didFail: CameraError.capture)
            }
            return
        }

        DispatchQueue.main.async {
            self.delegate?.cameraService(self, didCaptureJPEG: data)
        }
        sessionQueue.async {
            self.scheduleNextBurstCaptureIfNeeded()
        }
    }
}

enum CameraError: Error {
    case noBackCamera
    case configuration
    case capture
    case permissionDenied
}

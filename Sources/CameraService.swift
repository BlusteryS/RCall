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

    init(store: SessionStore = .shared) {
        self.store = store
        super.init()
    }

    func configure() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }

            do {
                let device = try self.selectBackCamera()
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                    throw CameraError.configuration
                }

                self.session.addInput(input)
                self.session.addOutput(self.output)
                self.configurePhotoDimensions(for: device)
                self.output.maxPhotoQualityPrioritization = .quality
                self.device = device
                self.disableAutoMacroIfAvailable(device)
                self.applyZoom(self.store.cameraZoom)
                self.session.commitConfiguration()
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async {
                    self.delegate?.cameraService(self, didFail: error)
                }
            }
        }
    }

    func start() {
        sessionQueue.async {
            guard !self.session.isRunning else {
                return
            }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else {
                return
            }
            self.session.stopRunning()
        }
    }

    func capture() {
        sessionQueue.async {
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.maxPhotoDimensions = self.output.maxPhotoDimensions
            settings.photoQualityPrioritization = .quality
            self.output.capturePhoto(with: settings, delegate: self)
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
}

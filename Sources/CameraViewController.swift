import AVFoundation
import UIKit

protocol CameraViewControllerDelegate: AnyObject {
    func cameraViewController(_ controller: CameraViewController, didCapture data: Data)
}

final class CameraViewController: UIViewController {
    weak var delegate: CameraViewControllerDelegate?

    private let camera = CameraService()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let shutterButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        camera.delegate = self
        build()
        camera.configure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        camera.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        camera.stop()
    }

    private func build() {
        let layer = AVCaptureVideoPreviewLayer(session: camera.session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer

        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Закрыть", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.42)
        closeButton.layer.cornerRadius = 18
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 38
        shutterButton.layer.borderWidth = 5
        shutterButton.layer.borderColor = UIColor.black.withAlphaComponent(0.25).cgColor
        shutterButton.addTarget(self, action: #selector(capture), for: .touchUpInside)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shutterButton)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 96),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -26),
            shutterButton.widthAnchor.constraint(equalToConstant: 76),
            shutterButton.heightAnchor.constraint(equalToConstant: 76)
        ])
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func capture() {
        shutterButton.isEnabled = false
        camera.capture()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            camera.beginZoom()
        case .changed:
            camera.zoom(scale: gesture.scale)
        default:
            break
        }
    }
}

extension CameraViewController: CameraServiceDelegate {
    func cameraService(_ service: CameraService, didCaptureJPEG data: Data) {
        delegate?.cameraViewController(self, didCapture: data)
        dismiss(animated: true)
    }

    func cameraService(_ service: CameraService, didFail error: Error) {
        shutterButton.isEnabled = true
        ToastPresenter.shared.show("Камера недоступна")
    }
}

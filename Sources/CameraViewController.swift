import AVFoundation
import UIKit

protocol CameraViewControllerDelegate: AnyObject {
    func cameraViewController(_ controller: CameraViewController, didCapture data: Data)
}

final class CameraViewController: UIViewController {
    weak var delegate: CameraViewControllerDelegate?

    private let camera: CameraService
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let shutterButton = UIButton(type: .system)
    private let seriesButton = UIButton(type: .system)
    private var expectedCaptures = 0
    private var completedCaptures = 0

    init(camera: CameraService) {
        self.camera = camera
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        camera.delegate = self
        build()
        camera.prepare()
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

        configureCaptureButton(shutterButton, title: nil, size: 76, borderWidth: 5)
        shutterButton.addTarget(self, action: #selector(captureSingle), for: .touchUpInside)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shutterButton)

        configureCaptureButton(seriesButton, title: "3", size: 64, borderWidth: 4)
        seriesButton.titleLabel?.font = .systemFont(ofSize: 26, weight: .black)
        seriesButton.addTarget(self, action: #selector(captureSeries), for: .touchUpInside)
        seriesButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(seriesButton)

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
            shutterButton.heightAnchor.constraint(equalToConstant: 76),
            seriesButton.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            seriesButton.leadingAnchor.constraint(equalTo: shutterButton.trailingAnchor, constant: 28),
            seriesButton.widthAnchor.constraint(equalToConstant: 64),
            seriesButton.heightAnchor.constraint(equalToConstant: 64)
        ])
    }

    private func configureCaptureButton(_ button: UIButton, title: String?, size: CGFloat, borderWidth: CGFloat) {
        button.setTitle(title, for: .normal)
        button.tintColor = .black
        button.backgroundColor = .white
        button.layer.cornerRadius = size / 2
        button.layer.borderWidth = borderWidth
        button.layer.borderColor = UIColor.black.withAlphaComponent(0.25).cgColor
    }

    private func capture(count: Int, interval: TimeInterval) {
        setCaptureButtonsEnabled(false)
        expectedCaptures = count
        completedCaptures = 0
        camera.capturePhotos(count: count, interval: interval)
    }

    private func setCaptureButtonsEnabled(_ enabled: Bool) {
        shutterButton.isEnabled = enabled
        seriesButton.isEnabled = enabled
        shutterButton.alpha = enabled ? 1 : 0.45
        seriesButton.alpha = enabled ? 1 : 0.45
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func captureSingle() {
        capture(count: 1, interval: 0)
    }

    @objc private func captureSeries() {
        capture(count: AppConfig.cameraSeriesCount, interval: AppConfig.cameraSeriesInterval)
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
        completedCaptures += 1
        if completedCaptures >= expectedCaptures {
            dismiss(animated: true)
        }
    }

    func cameraService(_ service: CameraService, didFail error: Error) {
        setCaptureButtonsEnabled(true)
        expectedCaptures = 0
        completedCaptures = 0
        ToastPresenter.shared.show("Камера недоступна")
    }
}

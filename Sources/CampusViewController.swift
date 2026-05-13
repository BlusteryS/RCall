import UIKit

protocol CampusViewControllerDelegate: AnyObject {
    func campusViewControllerDidTapCamera(_ controller: CampusViewController)
    func campusViewControllerDidTapChat(_ controller: CampusViewController)
    func campusViewController(_ controller: CampusViewController, signalBeganAt timestamp: Double)
    func campusViewController(_ controller: CampusViewController, signalEndedAt timestamp: Double)
}

final class CampusViewController: UIViewController {
    weak var delegate: CampusViewControllerDelegate?

    private let cameraButton = UIButton(type: .system)
    private let chatButton = UIButton(type: .system)
    private let signalButton = UIButton(type: .system)
    private var signalDown = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.background
        build()
    }

    private func build() {
        configure(button: cameraButton, title: "Камера", color: AppColors.camera, fontSize: 34)
        configure(button: chatButton, title: "Чат", color: AppColors.chat, fontSize: 22)
        configure(button: signalButton, title: "Звук", color: AppColors.signal, fontSize: 34)

        cameraButton.addTarget(self, action: #selector(openCamera), for: .touchUpInside)
        chatButton.addTarget(self, action: #selector(openChat), for: .touchUpInside)
        signalButton.addTarget(self, action: #selector(signalDownAction), for: [.touchDown, .touchDragEnter])
        signalButton.addTarget(self, action: #selector(signalUpAction), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])

        let stack = UIStackView(arrangedSubviews: [cameraButton, chatButton, signalButton])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            cameraButton.heightAnchor.constraint(equalTo: signalButton.heightAnchor),
            chatButton.heightAnchor.constraint(equalToConstant: 76)
        ])
    }

    private func configure(button: UIButton, title: String, color: UIColor, fontSize: CGFloat) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: fontSize, weight: .black)
        button.tintColor = .white
        button.backgroundColor = color
        button.layer.cornerRadius = 32
        button.layer.masksToBounds = true
    }

    @objc private func openCamera() {
        delegate?.campusViewControllerDidTapCamera(self)
    }

    @objc private func openChat() {
        delegate?.campusViewControllerDidTapChat(self)
    }

    @objc private func signalDownAction() {
        guard !signalDown else {
            return
        }

        signalDown = true
        signalButton.alpha = 0.72
        delegate?.campusViewController(self, signalBeganAt: Date().timeIntervalSince1970 * 1000)
    }

    @objc private func signalUpAction() {
        guard signalDown else {
            return
        }

        signalDown = false
        signalButton.alpha = 1
        delegate?.campusViewController(self, signalEndedAt: Date().timeIntervalSince1970 * 1000)
    }
}

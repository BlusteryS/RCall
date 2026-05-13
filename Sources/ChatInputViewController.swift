import UIKit

protocol ChatInputViewControllerDelegate: AnyObject {
    func chatInputViewController(_ controller: ChatInputViewController, didSubmit text: String)
}

final class ChatInputViewController: UIViewController, UITextFieldDelegate {
    weak var delegate: ChatInputViewControllerDelegate?

    private let field = UITextField()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        build()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        field.becomeFirstResponder()
    }

    private func build() {
        let container = UIView()
        container.backgroundColor = AppColors.panel
        container.layer.cornerRadius = 18
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        field.delegate = self
        field.placeholder = "Сообщение"
        field.returnKeyType = .send
        field.enablesReturnKeyAutomatically = true
        field.autocorrectionType = .no
        field.font = .systemFont(ofSize: 19, weight: .semibold)
        field.textColor = AppColors.ink
        field.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(field)

        let tap = UITapGestureRecognizer(target: self, action: #selector(close))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            container.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -10),
            container.heightAnchor.constraint(equalToConstant: 58),
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = (textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return false
        }

        delegate?.chatInputViewController(self, didSubmit: String(text.prefix(AppConfig.chatTextLimit)))
        dismiss(animated: true)
        return false
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

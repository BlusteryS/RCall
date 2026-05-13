import UIKit

protocol PinViewControllerDelegate: AnyObject {
    func pinViewController(_ controller: PinViewController, didSubmit pin: String)
}

final class PinViewController: UIViewController {
    weak var delegate: PinViewControllerDelegate?

    private let field = UITextField()
    private let button = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.background
        build()
    }

    func setBusy(_ busy: Bool) {
        button.isEnabled = !busy && (field.text?.count == 4)
        field.isEnabled = !busy
        button.setTitle(busy ? "Проверка" : "Продолжить", for: .normal)
    }

    private func build() {
        let title = UILabel()
        title.text = "Введите PIN"
        title.textColor = AppColors.ink
        title.font = .systemFont(ofSize: 34, weight: .black)
        title.textAlignment = .center

        field.keyboardType = .numberPad
        field.textContentType = .oneTimeCode
        field.textAlignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
        field.backgroundColor = AppColors.panel
        field.layer.cornerRadius = 18
        field.tintColor = AppColors.ink
        field.textColor = AppColors.ink
        field.addTarget(self, action: #selector(pinChanged), for: .editingChanged)

        button.setTitle("Продолжить", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.backgroundColor = AppColors.ink
        button.tintColor = .white
        button.layer.cornerRadius = 18
        button.isEnabled = false
        button.addTarget(self, action: #selector(submit), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [title, field, button])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 72),
            button.heightAnchor.constraint(equalToConstant: 62)
        ])
    }

    @objc private func pinChanged() {
        let digits = (field.text ?? "").filter(\.isNumber)
        field.text = String(digits.prefix(4))
        button.isEnabled = field.text?.count == 4
    }

    @objc private func submit() {
        guard let pin = field.text, pin.count == 4 else {
            return
        }

        delegate?.pinViewController(self, didSubmit: pin)
    }
}

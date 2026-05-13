import UIKit

final class ToastPresenter {
    static let shared = ToastPresenter()

    private weak var hostView: UIView?
    private var toastView: UIView?

    func attach(to view: UIView) {
        hostView = view
    }

    func show(_ text: String) {
        guard let hostView else {
            return
        }

        toastView?.removeFromSuperview()

        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.numberOfLines = 2

        let container = UIView()
        container.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        container.layer.cornerRadius = 14
        container.alpha = 0
        container.translatesAutoresizingMaskIntoConstraints = false

        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        hostView.addSubview(container)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            container.leadingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            container.bottomAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            container.trailingAnchor.constraint(lessThanOrEqualTo: hostView.trailingAnchor, constant: -16)
        ])

        toastView = container
        UIView.animate(withDuration: 0.15) {
            container.alpha = 1
        }

        UIView.animate(withDuration: 0.2, delay: 1.6) {
            container.alpha = 0
        } completion: { _ in
            container.removeFromSuperview()
        }
    }
}

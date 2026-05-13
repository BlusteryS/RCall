import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: MainCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        let coordinator = MainCoordinator(window: window)
        self.window = window
        self.coordinator = coordinator
        coordinator.start()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        coordinator?.resume()
    }
}

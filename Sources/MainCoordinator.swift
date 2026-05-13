import UIKit

final class MainCoordinator: NSObject {
    private let window: UIWindow
    private let api = APIClient()
    private let store = SessionStore.shared
    private lazy var uploadQueue = UploadQueue(api: api)
    private let rtcClient = WebRTCClient()
    private let audioKeeper = BackgroundAudioKeeper()
    private let cameraService = CameraService()

    private var realtimeClient: RealtimeClient?
    private var token: String?
    private var signalStart: Double?
    private var signalSequence = 0

    init(window: UIWindow) {
        self.window = window
        super.init()
        rtcClient.delegate = self
    }

    func start() {
        window.backgroundColor = AppColors.background
        window.makeKeyAndVisible()
        audioKeeper.start()
        ToastPresenter.shared.attach(to: window)

        if let token = store.token {
            self.token = token
            showCampus()
            Task { await restoreSession(token: token) }
        } else {
            showPin()
        }
    }

    func resume() {
        audioKeeper.start()
        rtcClient.markReady()
        if let token {
            uploadQueue.drain(token: token)
        }
    }

    private func restoreSession(token: String) async {
        do {
            let bootstrap = try await api.bootstrap(token: token)
            await MainActor.run {
                rtcClient.configure(rtc: bootstrap.rtc)
                connectRealtime(token: token)
            }
        } catch APIClientError.server(let status, _) where status == 401 {
            await MainActor.run {
                store.resetSession()
                self.token = nil
                showPin()
            }
        } catch {
            await MainActor.run {
                connectRealtime(token: token)
            }
        }
    }

    private func showPin() {
        let controller = PinViewController()
        controller.delegate = self
        window.rootViewController = controller
        ToastPresenter.shared.attach(to: window)
    }

    private func showCampus() {
        let controller = CampusViewController()
        controller.delegate = self
        window.rootViewController = controller
        ToastPresenter.shared.attach(to: window)
    }

    private func connectRealtime(token: String) {
        realtimeClient?.stop()
        let client = RealtimeClient(url: api.webSocketURL(token: token))
        client.delegate = self
        realtimeClient = client
        client.start()
    }

    private func sendSignalSegment(startedAt: Double, endedAt: Double) {
        guard endedAt >= startedAt else {
            return
        }

        signalSequence += 1
        let segment = AlarmSegment(
            id: UUID().uuidString.lowercased(),
            sequence: signalSequence,
            startedAt: startedAt,
            endedAt: endedAt
        )
        _ = realtimeClient?.send(.alarmSegment(segment))
    }
}

extension MainCoordinator: PinViewControllerDelegate {
    func pinViewController(_ controller: PinViewController, didSubmit pin: String) {
        controller.setBusy(true)
        Task {
            do {
                let ticket = try await api.verifyPin(pin)
                let token = try await api.createCampusSession(pinTicket: ticket, deviceId: store.deviceId)
                await MainActor.run {
                    store.token = token
                    self.token = token
                    controller.setBusy(false)
                    showCampus()
                }
                await restoreSession(token: token)
            } catch {
                await MainActor.run {
                    controller.setBusy(false)
                    ToastPresenter.shared.show("Неверный PIN")
                }
            }
        }
    }
}

extension MainCoordinator: CampusViewControllerDelegate {
    func campusViewControllerDidTapCamera(_ controller: CampusViewController) {
        cameraService.start()
        let camera = CameraViewController(camera: cameraService)
        camera.modalPresentationStyle = .fullScreen
        camera.delegate = self
        controller.present(camera, animated: true)
    }

    func campusViewControllerDidTapChat(_ controller: CampusViewController) {
        let chat = ChatInputViewController()
        chat.modalPresentationStyle = .overFullScreen
        chat.delegate = self
        controller.present(chat, animated: false)
    }

    func campusViewController(_ controller: CampusViewController, signalBeganAt timestamp: Double) {
        signalStart = timestamp
    }

    func campusViewController(_ controller: CampusViewController, signalEndedAt timestamp: Double) {
        guard let startedAt = signalStart else {
            return
        }

        signalStart = nil
        sendSignalSegment(startedAt: startedAt, endedAt: timestamp)
    }
}

extension MainCoordinator: CameraViewControllerDelegate {
    func cameraViewController(_ controller: CameraViewController, didCapture data: Data) {
        guard let token else {
            ToastPresenter.shared.show("Нет сессии")
            return
        }

        uploadQueue.enqueueImage(data, token: token)
    }
}

extension MainCoordinator: ChatInputViewControllerDelegate {
    func chatInputViewController(_ controller: ChatInputViewController, didSubmit text: String) {
        guard let token else {
            ToastPresenter.shared.show("Нет сессии")
            return
        }

        uploadQueue.enqueueChat(text, token: token)
    }
}

extension MainCoordinator: RealtimeClientDelegate {
    func realtimeClientDidConnect(_ client: RealtimeClient) {
        rtcClient.markReady()
        if let token {
            uploadQueue.drain(token: token)
        }
    }

    func realtimeClient(_ client: RealtimeClient, didReceive message: RealtimeMessage) {
        rtcClient.handle(message)
    }

    func realtimeClientDidDisconnect(_ client: RealtimeClient) {
        rtcClient.repair()
    }

    func realtimeClientNetworkPathDidChange(_ client: RealtimeClient) {
        rtcClient.forceNetworkRepair()
    }
}

extension MainCoordinator: WebRTCClientDelegate {
    func webRTCClientNeedsSend(_ message: OutgoingRealtimeMessage) {
        _ = realtimeClient?.send(message)
    }

    func webRTCClientDidChangeConnection(connected: Bool) {
        if connected {
            audioKeeper.start()
        }
    }
}

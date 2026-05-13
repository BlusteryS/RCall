import Foundation

final class UploadQueue {
    private let api: APIClient
    private var imageQueue: [Data] = []
    private var chatQueue: [String] = []
    private var uploading = false

    init(api: APIClient) {
        self.api = api
    }

    func enqueueImage(_ data: Data, token: String) {
        imageQueue.append(data)
        drain(token: token)
    }

    func enqueueChat(_ text: String, token: String) {
        chatQueue.append(text)
        drain(token: token)
    }

    func drain(token: String) {
        guard !uploading else {
            return
        }

        uploading = true
        Task {
            await drainLoop(token: token)
        }
    }

    private func drainLoop(token: String) async {
        defer { uploading = false }

        while !imageQueue.isEmpty || !chatQueue.isEmpty {
            if !imageQueue.isEmpty {
                let data = imageQueue[0]
                do {
                    _ = try await api.uploadCameraImage(data, token: token)
                    imageQueue.removeFirst()
                    await MainActor.run {
                        ToastPresenter.shared.show("Фото отправлено")
                    }
                } catch {
                    await MainActor.run {
                        ToastPresenter.shared.show("Фото будет отправлено позже")
                    }
                    return
                }
                continue
            }

            if !chatQueue.isEmpty {
                let text = chatQueue[0]
                do {
                    _ = try await api.sendChatMessage(text, token: token)
                    chatQueue.removeFirst()
                    await MainActor.run {
                        ToastPresenter.shared.show("Сообщение отправлено")
                    }
                } catch {
                    await MainActor.run {
                        ToastPresenter.shared.show("Сообщение будет отправлено позже")
                    }
                    return
                }
            }
        }
    }
}

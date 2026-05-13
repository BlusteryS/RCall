import Foundation

enum APIClientError: Error {
    case invalidResponse
    case server(status: Int, message: String)
}

final class APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL = AppConfig.apiBaseURL, session: URLSession = APIClient.makeSession()) {
        self.baseURL = baseURL
        self.session = session
    }

    func verifyPin(_ pin: String) async throws -> String {
        let payload = ["pin": pin]
        let response: PinResponse = try await jsonRequest(
            path: "/api/pin",
            method: "POST",
            body: encoder.encode(payload),
            headers: ["Content-Type": "application/json"]
        )
        return response.pinTicket
    }

    func createCampusSession(pinTicket: String, deviceId: String) async throws -> String {
        let body: [String: String] = [
            "role": AppConfig.role,
            "pinTicket": pinTicket,
            "deviceId": deviceId
        ]
        let response: SessionResponse = try await jsonRequest(
            path: "/api/sessions",
            method: "POST",
            body: encoder.encode(body),
            headers: ["Content-Type": "application/json"]
        )
        return response.token
    }

    func bootstrap(token: String) async throws -> BootstrapResponse {
        try await jsonRequest(path: "/api/bootstrap", method: "GET", token: token)
    }

    func uploadCameraImage(_ data: Data, token: String) async throws -> Attachment {
        let response: UploadAttachmentResponse = try await jsonRequest(
            path: "/api/attachments",
            method: "POST",
            token: token,
            body: data,
            headers: ["Content-Type": "image/jpeg"]
        )
        return response.attachment
    }

    func sendChatMessage(_ text: String, token: String) async throws -> ChatMessage {
        let response: SendChatResponse = try await jsonRequest(
            path: "/api/chat",
            method: "POST",
            token: token,
            body: encoder.encode(["text": text]),
            headers: ["Content-Type": "application/json"]
        )
        return response.message
    }

    func webSocketURL(token: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url!
    }

    private func jsonRequest<T: Decodable>(
        path: String,
        method: String,
        token: String? = nil,
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> T {
        var request = URLRequest(url: url(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 60

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ServerError.self, from: data).message) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw APIClientError.server(status: http.statusCode, message: message)
        }

        return try decoder.decode(T.self, from: data)
    }

    private func url(path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        return components.url!
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 180
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil

        return URLSession(configuration: configuration)
    }
}

private struct ServerError: Decodable {
    let message: String
}

import Foundation

/// One conversation at a time; mirrors the Android client's RealtimeClient.
final class RealtimeClient {
    var onMessage: ((Message) -> Void)?
    var onTyping: ((String) -> Void)?
    var onRead: ((Int64) -> Void)?
    var onState: ((Bool) -> Void)?

    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    func connect(baseURL: String, chatId: String, token: String) {
        disconnect()

        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasPrefix("https://") {
            base = "wss://" + base.dropFirst("https://".count)
        } else if base.hasPrefix("http://") {
            base = "ws://" + base.dropFirst("http://".count)
        }
        while base.hasSuffix("/") { base.removeLast() }

        guard var components = URLComponents(string: base + "/api/ws") else { return }
        components.queryItems = [
            URLQueryItem(name: "chat", value: chatId),
            URLQueryItem(name: "token", value: token),
        ]
        guard let url = components.url else { return }

        let socket = session.webSocketTask(with: url)
        task = socket
        socket.resume()
        onState?(true)
        receive()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.handle(text)
                }
                self.receive()
            case .failure:
                self.onState?(false)
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return }

        switch type {
        case "message":
            if let payload = object["message"],
               let payloadData = try? JSONSerialization.data(withJSONObject: payload),
               let message = try? JSONDecoder().decode(Message.self, from: payloadData) {
                onMessage?(message)
            }
        case "typing":
            onTyping?(object["name"] as? String ?? "")
        case "read":
            onRead?((object["seq"] as? NSNumber)?.int64Value ?? 0)
        default:
            break
        }
    }

    func sendTyping() {
        task?.send(.string("{\"type\":\"typing\"}")) { _ in }
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
}

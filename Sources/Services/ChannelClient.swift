import Foundation
import os.log

private let logger = Logger(subsystem: "com.teambrilliant.claude-peek", category: "Channel")

/// Checks if the MCP channel server is running and sends replies to it
@MainActor
final class ChannelClient: ObservableObject {
    static let shared = ChannelClient()

    @Published private(set) var isAvailable = false

    private let port: Int
    private let baseURL: URL
    private var checkTimer: Timer?

    private init() {
        self.port = Int(ProcessInfo.processInfo.environment["CLAUDE_PEEK_MCP_PORT"] ?? "7778") ?? 7778
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
    }

    func startMonitoring() {
        checkAvailability()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAvailability()
            }
        }
    }

    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// Send a reply message to the MCP channel server
    func sendReply(text: String, sessionId: String) async -> Bool {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["text": text, "session_id": sessionId]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = data

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            if success {
                logger.debug("Reply sent for \(sessionId.prefix(8), privacy: .public)")
            }
            return success
        } catch {
            logger.debug("Reply failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func checkAvailability() {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 1

        Task {
            let available: Bool
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                // Server returns 405 for GET (POST only) — that means it's running
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                available = code == 405 || code == 200
            } catch {
                available = false
            }

            await MainActor.run {
                if self.isAvailable != available {
                    self.isAvailable = available
                    logger.info("Channel \(available ? "available" : "unavailable", privacy: .public)")
                }
            }
        }
    }
}

import Foundation
import os.log

private let logger = Logger(subsystem: "com.teambrilliant.claude-peek", category: "Channel")

/// Tracks MCP channel servers per session and routes replies to the correct one
@MainActor
final class ChannelClient: ObservableObject {
    static let shared = ChannelClient()

    /// Ports registered by MCP channel servers, keyed by cwd (matches session lookup)
    @Published private(set) var registeredPorts: [String: Int] = [:]

    private init() {}

    /// Register a channel server's port for a session (called from SocketServer on ChannelRegistration event)
    func registerPort(_ port: Int, cwd: String) {
        registeredPorts[cwd] = port
        logger.info("Channel registered: port \(port) for \(cwd, privacy: .public)")
    }

    /// Check if a session has a channel available
    func isAvailable(cwd: String) -> Bool {
        registeredPorts[cwd] != nil
    }

    /// Send a reply message to the correct MCP channel server for this session
    func sendReply(text: String, sessionId: String, cwd: String) async -> Bool {
        guard let port = registeredPorts[cwd] else {
            logger.debug("No channel port for \(cwd, privacy: .public)")
            return false
        }

        let url = URL(string: "http://127.0.0.1:\(port)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["text": text, "session_id": sessionId]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }
        request.httpBody = data

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            if success {
                logger.debug("Reply sent to port \(port) for \(sessionId.prefix(8), privacy: .public)")
            }
            return success
        } catch {
            // Port no longer responding — remove registration
            registeredPorts.removeValue(forKey: cwd)
            logger.debug("Reply failed, removed port \(port): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

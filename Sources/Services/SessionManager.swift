import Foundation
import os.log

private let logger = Logger(subsystem: "com.teambrilliant.claude-peek", category: "Sessions")

@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published private(set) var sessions: [String: SessionState] = [:]

    /// Tool names auto-approved for the rest of a session, keyed by sessionId
    private var sessionAllowRules: [String: Set<String>] = [:]

    var activeSessions: [SessionState] {
        sessions.values
            .filter { $0.phase != .ended }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    var pendingSessions: [SessionState] {
        sessions.values.filter { $0.phase.isWaitingForApproval }
    }

    private init() {}

    func startListening() {
        SocketServer.shared.start { [weak self] event in
            Task { @MainActor in
                self?.processEvent(event)
            }
        }
    }

    func approvePermission(sessionId: String) {
        guard let session = sessions[sessionId],
            let permission = session.activePermission
        else { return }

        SocketServer.shared.respondToPermission(
            toolUseId: permission.toolUseId, decision: "allow")

        sessions[sessionId]?.phase = .processing
        sessions[sessionId]?.lastActivity = Date()
        logger.info("Approved \(permission.toolName) for \(sessionId.prefix(8), privacy: .public)")
    }

    func approvePermissionAlways(sessionId: String) {
        guard let session = sessions[sessionId],
            let permission = session.activePermission
        else { return }

        // Add rule for this tool name in this session
        sessionAllowRules[sessionId, default: []].insert(permission.toolName)

        SocketServer.shared.respondToPermission(
            toolUseId: permission.toolUseId, decision: "allow")

        sessions[sessionId]?.phase = .processing
        sessions[sessionId]?.lastActivity = Date()
        logger.info("Always-approved \(permission.toolName) for session \(sessionId.prefix(8), privacy: .public)")
    }

    func denyPermission(sessionId: String, reason: String?) {
        guard let session = sessions[sessionId],
            let permission = session.activePermission
        else { return }

        SocketServer.shared.respondToPermission(
            toolUseId: permission.toolUseId,
            decision: "deny",
            reason: reason ?? "Denied via Claude Peek")

        sessions[sessionId]?.phase = .idle
        sessions[sessionId]?.lastActivity = Date()
        logger.info("Denied \(permission.toolName) for \(sessionId.prefix(8), privacy: .public)")
    }

    // MARK: - Event Processing

    private func processEvent(_ event: HookEvent) {
        let sessionId = event.sessionId
        let targetPhase = event.determinePhase()

        // Create session if needed
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionState(
                sessionId: sessionId,
                cwd: event.cwd,
                pid: event.pid
            )
            loadDisplayName(sessionId: sessionId, cwd: event.cwd)
            logger.info("New session \(sessionId.prefix(8), privacy: .public) at \(event.cwd, privacy: .public)")
        }

        // Update PID if provided
        if let pid = event.pid {
            sessions[sessionId]?.pid = pid
        }

        // PostToolUse cancels specific pending permission (tool was approved in terminal)
        if event.event == "PostToolUse", let toolUseId = event.toolUseId {
            SocketServer.shared.cancelPendingPermission(toolUseId: toolUseId)
        }

        // Skip permission_prompt notifications (PermissionRequest handles it)
        if event.event == "Notification" && event.notificationType == "permission_prompt" {
            return
        }

        // Auto-approve if tool name matches a session allow rule
        if case .waitingForApproval(let ctx) = targetPhase,
            let rules = sessionAllowRules[sessionId],
            rules.contains(ctx.toolName)
        {
            SocketServer.shared.respondToPermission(
                toolUseId: ctx.toolUseId, decision: "allow")
            sessions[sessionId]?.phase = .processing
            sessions[sessionId]?.lastActivity = Date()
            logger.info("Auto-approved \(ctx.toolName) for \(sessionId.prefix(8), privacy: .public)")
            return
        }

        // Validate state transition
        guard let currentPhase = sessions[sessionId]?.phase,
            currentPhase.canTransition(to: targetPhase)
        else {
            logger.debug(
                "Invalid transition \(self.sessions[sessionId]?.phase.description ?? "nil") → \(targetPhase) for \(sessionId.prefix(8), privacy: .public)"
            )
            return
        }

        sessions[sessionId]?.phase = targetPhase
        sessions[sessionId]?.lastActivity = Date()

        logger.debug("\(sessionId.prefix(8), privacy: .public) → \(targetPhase)")

        // Clean up ended sessions after delay
        if case .ended = targetPhase {
            SocketServer.shared.cancelPendingPermissions(sessionId: sessionId)
            sessionAllowRules.removeValue(forKey: sessionId)
            let capturedId = sessionId
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(30))
                if self?.sessions[capturedId]?.phase == .ended {
                    self?.sessions.removeValue(forKey: capturedId)
                    logger.debug("Removed ended session \(capturedId.prefix(8), privacy: .public)")
                }
            }
        }
    }

    /// Load display name from JSONL custom-title entry (set via /rename)
    private func loadDisplayName(sessionId: String, cwd: String) {
        guard let file = SessionFileMapper.jsonlPath(cwd: cwd, sessionId: sessionId) else { return }

        Task.detached { [weak self] in
            guard let data = try? Data(contentsOf: file) else { return }
            let lines = data.split(separator: UInt8(ascii: "\n"))

            for line in lines {
                guard let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                    entry["type"] as? String == "custom-title",
                    let title = entry["customTitle"] as? String
                else { continue }

                await MainActor.run { [weak self] in
                    self?.sessions[sessionId]?.displayName = title
                }
                return
            }
        }
    }
}

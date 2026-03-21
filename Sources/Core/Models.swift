import Foundation

// MARK: - AnyCodable

struct AnyCodable: Codable, @unchecked Sendable {
    nonisolated(unsafe) let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Cannot decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: [], debugDescription: "Cannot encode value"))
        }
    }
}

// MARK: - PermissionContext

struct PermissionContext: Equatable, Sendable {
    let toolUseId: String
    let toolName: String
    let toolInput: [String: AnyCodable]?
    let receivedAt: Date

    var formattedInput: String? {
        guard let input = toolInput else { return nil }
        var parts: [String] = []
        for (key, value) in input {
            let valueStr: String
            switch value.value {
            case let str as String:
                valueStr = str.count > 100 ? String(str.prefix(100)) + "..." : str
            case let num as Int:
                valueStr = String(num)
            case let num as Double:
                valueStr = String(num)
            case let bool as Bool:
                valueStr = bool ? "true" : "false"
            default:
                valueStr = "..."
            }
            parts.append("\(key): \(valueStr)")
        }
        return parts.joined(separator: "\n")
    }

    nonisolated static func == (lhs: PermissionContext, rhs: PermissionContext) -> Bool {
        lhs.toolUseId == rhs.toolUseId
            && lhs.toolName == rhs.toolName
            && lhs.receivedAt == rhs.receivedAt
    }
}

// MARK: - SessionPhase

enum SessionPhase: Sendable, Equatable, CustomStringConvertible {
    case idle
    case processing
    case waitingForInput
    case waitingForApproval(PermissionContext)
    case compacting
    case ended

    nonisolated func canTransition(to next: SessionPhase) -> Bool {
        switch (self, next) {
        case (.ended, _): return false
        case (_, .ended): return true
        case (.idle, .processing),
            (.idle, .waitingForApproval),
            (.idle, .compacting): return true
        case (.processing, .waitingForInput),
            (.processing, .waitingForApproval),
            (.processing, .compacting),
            (.processing, .idle): return true
        case (.waitingForInput, .processing),
            (.waitingForInput, .idle),
            (.waitingForInput, .compacting): return true
        case (.waitingForApproval, .processing),
            (.waitingForApproval, .idle),
            (.waitingForApproval, .waitingForInput),
            (.waitingForApproval, .waitingForApproval): return true
        case (.compacting, .processing),
            (.compacting, .idle),
            (.compacting, .waitingForInput): return true
        default: return self == next
        }
    }

    var needsAttention: Bool {
        switch self {
        case .waitingForApproval, .waitingForInput: return true
        default: return false
        }
    }

    var isActive: Bool {
        switch self {
        case .processing, .compacting: return true
        default: return false
        }
    }

    var isWaitingForApproval: Bool {
        if case .waitingForApproval = self { return true }
        return false
    }

    var approvalToolName: String? {
        if case .waitingForApproval(let ctx) = self { return ctx.toolName }
        return nil
    }

    nonisolated static func == (lhs: SessionPhase, rhs: SessionPhase) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
            (.processing, .processing),
            (.waitingForInput, .waitingForInput),
            (.compacting, .compacting),
            (.ended, .ended): return true
        case (.waitingForApproval(let a), .waitingForApproval(let b)): return a == b
        default: return false
        }
    }

    nonisolated var description: String {
        switch self {
        case .idle: "idle"
        case .processing: "processing"
        case .waitingForInput: "waitingForInput"
        case .waitingForApproval(let ctx): "waitingForApproval(\(ctx.toolName))"
        case .compacting: "compacting"
        case .ended: "ended"
        }
    }
}

// MARK: - SessionState

struct SessionState: Equatable, Identifiable, Sendable {
    let sessionId: String
    let cwd: String
    let projectName: String
    var displayName: String?
    var pid: Int?
    var phase: SessionPhase
    var lastActivity: Date
    let createdAt: Date

    var id: String { sessionId }

    /// Best available name: displayName > projectName
    var title: String { displayName ?? projectName }

    init(
        sessionId: String,
        cwd: String,
        projectName: String? = nil,
        displayName: String? = nil,
        pid: Int? = nil,
        phase: SessionPhase = .idle,
        lastActivity: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.projectName = projectName ?? URL(fileURLWithPath: cwd).lastPathComponent
        self.displayName = displayName
        self.pid = pid
        self.phase = phase
        self.lastActivity = lastActivity
        self.createdAt = createdAt
    }

    var activePermission: PermissionContext? {
        if case .waitingForApproval(let ctx) = phase { return ctx }
        return nil
    }
}

// MARK: - HookEvent

struct HookEvent: Codable, Sendable {
    let sessionId: String
    let cwd: String
    let event: String
    let status: String
    let pid: Int?
    let tty: String?
    let tool: String?
    let toolInput: [String: AnyCodable]?
    let toolUseId: String?
    let notificationType: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd, event, status, pid, tty, tool
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case notificationType = "notification_type"
        case message
    }

    var expectsResponse: Bool {
        event == "PermissionRequest" && status == "waiting_for_approval"
    }

    func determinePhase() -> SessionPhase {
        if event == "PreCompact" {
            return .compacting
        }

        if expectsResponse, let tool {
            return .waitingForApproval(PermissionContext(
                toolUseId: toolUseId ?? "",
                toolName: tool,
                toolInput: toolInput,
                receivedAt: Date()
            ))
        }

        if event == "Notification" && notificationType == "idle_prompt" {
            return .idle
        }

        switch status {
        case "waiting_for_input": return .waitingForInput
        case "running_tool", "processing", "starting": return .processing
        case "compacting": return .compacting
        case "ended": return .ended
        default: return .idle
        }
    }
}

// MARK: - HookResponse

struct HookResponse: Codable {
    let decision: String
    let reason: String?
}

import Foundation
import os.log

private let logger = Logger(subsystem: "com.teambrilliant.claude-peek", category: "Socket")

struct PendingPermission: Sendable {
    let sessionId: String
    let toolUseId: String
    let clientSocket: Int32
    let event: HookEvent
    let receivedAt: Date
}

final class SocketServer: Sendable {
    static let shared = SocketServer()
    static let socketPath = "/tmp/claude-peek.sock"

    private let queue = DispatchQueue(label: "com.teambrilliant.claude-peek.socket", qos: .userInitiated)

    // nonisolated(unsafe) because all access is serialized on `queue`
    nonisolated(unsafe) private var serverSocket: Int32 = -1
    nonisolated(unsafe) private var acceptSource: DispatchSourceRead?
    nonisolated(unsafe) private var eventHandler: (@Sendable (HookEvent) -> Void)?
    nonisolated(unsafe) private var pendingPermissions: [String: PendingPermission] = [:]
    nonisolated(unsafe) private var toolUseIdCache: [String: [String]] = [:]

    private let permissionsLock = NSLock()
    private let cacheLock = NSLock()

    private init() {}

    func start(onEvent: @escaping @Sendable (HookEvent) -> Void) {
        queue.async { [self] in
            startServer(onEvent: onEvent)
        }
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        unlink(Self.socketPath)

        permissionsLock.lock()
        for (_, pending) in pendingPermissions {
            close(pending.clientSocket)
        }
        pendingPermissions.removeAll()
        permissionsLock.unlock()
    }

    func respondToPermission(toolUseId: String, decision: String, reason: String? = nil) {
        queue.async { [self] in
            sendPermissionResponse(toolUseId: toolUseId, decision: decision, reason: reason)
        }
    }

    func cancelPendingPermissions(sessionId: String) {
        queue.async { [self] in
            cleanupPendingPermissions(sessionId: sessionId)
        }
    }

    func cancelPendingPermission(toolUseId: String) {
        queue.async { [self] in
            permissionsLock.lock()
            guard let pending = pendingPermissions.removeValue(forKey: toolUseId) else {
                permissionsLock.unlock()
                return
            }
            permissionsLock.unlock()
            logger.debug("Tool completed externally, closing socket for \(pending.sessionId.prefix(8), privacy: .public)")
            close(pending.clientSocket)
        }
    }

    // MARK: - Private

    private func startServer(onEvent: @escaping @Sendable (HookEvent) -> Void) {
        guard serverSocket < 0 else { return }
        eventHandler = onEvent

        unlink(Self.socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            logger.error("Failed to create socket: \(errno)")
            return
        }

        let flags = fcntl(serverSocket, F_GETFL)
        _ = fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        Self.socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                let pathBufferPtr = UnsafeMutableRawPointer(pathPtr)
                    .assumingMemoryBound(to: CChar.self)
                strcpy(pathBufferPtr, ptr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            logger.error("Failed to bind socket: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        chmod(Self.socketPath, 0o700)

        guard listen(serverSocket, 10) == 0 else {
            logger.error("Failed to listen: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        logger.info("Listening on \(Self.socketPath, privacy: .public)")

        acceptSource = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: queue)
        acceptSource?.setEventHandler { [self] in
            acceptConnection()
        }
        acceptSource?.setCancelHandler { [self] in
            if serverSocket >= 0 {
                close(serverSocket)
                serverSocket = -1
            }
        }
        acceptSource?.resume()
    }

    private func acceptConnection() {
        let clientSocket = accept(serverSocket, nil, nil)
        guard clientSocket >= 0 else { return }

        var nosigpipe: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        handleClient(clientSocket)
    }

    private func handleClient(_ clientSocket: Int32) {
        let flags = fcntl(clientSocket, F_GETFL)
        _ = fcntl(clientSocket, F_SETFL, flags | O_NONBLOCK)

        var allData = Data()
        var buffer = [UInt8](repeating: 0, count: 131_072)
        var pollFd = pollfd(fd: clientSocket, events: Int16(POLLIN), revents: 0)

        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 0.5 {
            let pollResult = poll(&pollFd, 1, 50)

            if pollResult > 0 && (pollFd.revents & Int16(POLLIN)) != 0 {
                let bytesRead = read(clientSocket, &buffer, buffer.count)
                if bytesRead > 0 {
                    allData.append(contentsOf: buffer[0..<bytesRead])
                } else if bytesRead == 0 {
                    break
                } else if errno != EAGAIN && errno != EWOULDBLOCK {
                    break
                }
            } else if pollResult == 0 {
                if !allData.isEmpty { break }
            } else {
                break
            }
        }

        guard !allData.isEmpty else {
            close(clientSocket)
            return
        }

        guard let event = try? JSONDecoder().decode(HookEvent.self, from: allData) else {
            logger.warning("Failed to parse event")
            close(clientSocket)
            return
        }

        logger.debug("Received: \(event.event, privacy: .public) for \(event.sessionId.prefix(8), privacy: .public)")

        if event.event == "PreToolUse" {
            cacheToolUseId(event: event)
        }

        if event.event == "SessionEnd" {
            cleanupCache(sessionId: event.sessionId)
        }

        if event.expectsResponse {
            let toolUseId: String
            if let eventToolUseId = event.toolUseId {
                toolUseId = eventToolUseId
            } else if let cachedId = popCachedToolUseId(event: event) {
                toolUseId = cachedId
            } else {
                logger.warning("Permission request missing tool_use_id")
                close(clientSocket)
                eventHandler?(event)
                return
            }

            let updatedEvent = HookEvent(
                sessionId: event.sessionId,
                cwd: event.cwd,
                event: event.event,
                status: event.status,
                pid: event.pid,
                tty: event.tty,
                tool: event.tool,
                toolInput: event.toolInput,
                toolUseId: toolUseId,
                notificationType: event.notificationType,
                message: event.message
            )

            let pending = PendingPermission(
                sessionId: event.sessionId,
                toolUseId: toolUseId,
                clientSocket: clientSocket,
                event: updatedEvent,
                receivedAt: Date()
            )

            permissionsLock.lock()
            pendingPermissions[toolUseId] = pending
            permissionsLock.unlock()

            eventHandler?(updatedEvent)
            return
        }

        close(clientSocket)
        eventHandler?(event)
    }

    // MARK: - Permission Response

    private func sendPermissionResponse(toolUseId: String, decision: String, reason: String?) {
        permissionsLock.lock()
        guard let pending = pendingPermissions.removeValue(forKey: toolUseId) else {
            permissionsLock.unlock()
            return
        }
        permissionsLock.unlock()

        let response = HookResponse(decision: decision, reason: reason)
        guard let data = try? JSONEncoder().encode(response) else {
            close(pending.clientSocket)
            return
        }

        let age = Date().timeIntervalSince(pending.receivedAt)
        logger.info("Sending \(decision, privacy: .public) for \(pending.sessionId.prefix(8), privacy: .public) (age: \(String(format: "%.1f", age))s)")

        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            _ = write(pending.clientSocket, baseAddress, data.count)
        }

        close(pending.clientSocket)
    }

    private func cleanupPendingPermissions(sessionId: String) {
        permissionsLock.lock()
        let matching = pendingPermissions.filter { $0.value.sessionId == sessionId }
        for (toolUseId, pending) in matching {
            close(pending.clientSocket)
            pendingPermissions.removeValue(forKey: toolUseId)
        }
        permissionsLock.unlock()
    }

    // MARK: - Tool Use ID Cache

    private static let sortedEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private func cacheKey(sessionId: String, toolName: String?, toolInput: [String: AnyCodable]?) -> String {
        let inputStr: String
        if let input = toolInput,
            let data = try? Self.sortedEncoder.encode(input),
            let str = String(data: data, encoding: .utf8)
        {
            inputStr = str
        } else {
            inputStr = "{}"
        }
        return "\(sessionId):\(toolName ?? "unknown"):\(inputStr)"
    }

    private func cacheToolUseId(event: HookEvent) {
        guard let toolUseId = event.toolUseId else { return }
        let key = cacheKey(sessionId: event.sessionId, toolName: event.tool, toolInput: event.toolInput)

        cacheLock.lock()
        if toolUseIdCache[key] == nil {
            toolUseIdCache[key] = []
        }
        toolUseIdCache[key]?.append(toolUseId)
        cacheLock.unlock()
    }

    private func popCachedToolUseId(event: HookEvent) -> String? {
        let key = cacheKey(sessionId: event.sessionId, toolName: event.tool, toolInput: event.toolInput)

        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard var queue = toolUseIdCache[key], !queue.isEmpty else { return nil }
        let toolUseId = queue.removeFirst()

        if queue.isEmpty {
            toolUseIdCache.removeValue(forKey: key)
        } else {
            toolUseIdCache[key] = queue
        }

        return toolUseId
    }

    private func cleanupCache(sessionId: String) {
        cacheLock.lock()
        let keysToRemove = toolUseIdCache.keys.filter { $0.hasPrefix("\(sessionId):") }
        for key in keysToRemove {
            toolUseIdCache.removeValue(forKey: key)
        }
        cacheLock.unlock()
    }
}


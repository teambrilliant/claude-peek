import Foundation
import os.log

private let logger = Logger(subsystem: "com.teambrilliant.claude-peek", category: "Conversation")

// MARK: - Conversation Message Types

enum ConversationRole {
    case user
    case assistant
}

struct ToolCallInfo: Identifiable {
    let id: String
    let name: String
    let inputSummary: String
}

enum MessageContent {
    case text(String)
    case toolUse(ToolCallInfo)
    case thinking(String)
}

struct ConversationMessage: Identifiable {
    let id: String
    let role: ConversationRole
    let content: [MessageContent]
    let timestamp: Date

    var textContent: String {
        content.compactMap {
            if case .text(let text) = $0 { return text }
            return nil
        }.joined(separator: "\n")
    }
}

// MARK: - Parser

final class ConversationParser {
    private let maxMessages = 50
    private var lastOffset: UInt64 = 0
    private var messages: [ConversationMessage] = []
    private(set) var customTitle: String?
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var currentMessages: [ConversationMessage] { messages }

    /// Parse the JSONL file, returns messages newest-last
    func parse(file: URL) -> [ConversationMessage] {
        guard let data = try? Data(contentsOf: file) else { return messages }

        let lines = data.split(separator: UInt8(ascii: "\n"))
        lastOffset = UInt64(data.count)

        var parsed: [ConversationMessage] = []

        for line in lines {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                let type = entry["type"] as? String
            else { continue }

            switch type {
            case "user":
                if let msg = parseUserEntry(entry) {
                    parsed.append(msg)
                }
            case "assistant":
                if let msg = parseAssistantEntry(entry) {
                    parsed.append(msg)
                }
            case "custom-title":
                if let title = entry["customTitle"] as? String {
                    customTitle = title
                }
            default:
                continue
            }
        }

        // Keep last N messages
        messages = Array(parsed.suffix(maxMessages))
        return messages
    }

    /// Incremental parse — only read new bytes since last parse
    func parseIncremental(file: URL) -> [ConversationMessage] {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return messages }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        guard fileSize > lastOffset else { return messages }

        handle.seek(toFileOffset: lastOffset)
        let newData = handle.readDataToEndOfFile()
        lastOffset = fileSize

        let lines = newData.split(separator: UInt8(ascii: "\n"))
        var hasNew = false

        for line in lines {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                let type = entry["type"] as? String
            else { continue }

            switch type {
            case "user":
                if let msg = parseUserEntry(entry) {
                    messages.append(msg)
                    hasNew = true
                }
            case "assistant":
                if let msg = parseAssistantEntry(entry) {
                    messages.append(msg)
                    hasNew = true
                }
            case "custom-title":
                if let title = entry["customTitle"] as? String {
                    customTitle = title
                }
            default:
                continue
            }
        }

        if hasNew {
            // Trim to max
            messages = Array(messages.suffix(maxMessages))
        }

        return messages
    }

    func reset() {
        lastOffset = 0
        messages = []
        customTitle = nil
    }

    // MARK: - Entry Parsing

    private func parseUserEntry(_ entry: [String: Any]) -> ConversationMessage? {
        guard let uuid = entry["uuid"] as? String,
            let message = entry["message"] as? [String: Any]
        else { return nil }

        let timestamp = parseTimestamp(entry["timestamp"])

        let text: String
        if let content = message["content"] as? String {
            text = content
        } else if let contentBlocks = message["content"] as? [[String: Any]] {
            text = contentBlocks.compactMap { block in
                if block["type"] as? String == "text" {
                    return block["text"] as? String
                }
                return nil
            }.joined(separator: "\n")
        } else {
            return nil
        }

        guard !text.isEmpty else { return nil }

        return ConversationMessage(
            id: uuid,
            role: .user,
            content: [.text(text)],
            timestamp: timestamp
        )
    }

    private func parseAssistantEntry(_ entry: [String: Any]) -> ConversationMessage? {
        guard let uuid = entry["uuid"] as? String,
            let message = entry["message"] as? [String: Any],
            let contentBlocks = message["content"] as? [[String: Any]]
        else { return nil }

        let timestamp = parseTimestamp(entry["timestamp"])
        var content: [MessageContent] = []

        for block in contentBlocks {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty {
                    content.append(.text(text))
                }
            case "tool_use":
                if let id = block["id"] as? String,
                    let name = block["name"] as? String
                {
                    // Show claude-peek reply as normal text, not a tool call
                    if name == "mcp__claude-peek__reply",
                        let input = block["input"] as? [String: Any],
                        let text = input["text"] as? String, !text.isEmpty
                    {
                        content.append(.text(text))
                    } else if name == "ToolSearch",
                        let input = block["input"] as? [String: Any],
                        let query = input["query"] as? String,
                        query.contains("claude-peek")
                    {
                        // Hide ToolSearch for claude-peek tools
                    } else {
                        let inputSummary = summarizeToolInput(
                            name: name, input: block["input"] as? [String: Any])
                        content.append(.toolUse(ToolCallInfo(
                            id: id, name: name, inputSummary: inputSummary)))
                    }
                }
            case "thinking":
                if let thinking = block["thinking"] as? String, !thinking.isEmpty {
                    content.append(.thinking(thinking))
                }
            default:
                continue
            }
        }

        guard !content.isEmpty else { return nil }

        return ConversationMessage(
            id: uuid,
            role: .assistant,
            content: content,
            timestamp: timestamp
        )
    }

    private func parseTimestamp(_ value: Any?) -> Date {
        guard let str = value as? String else { return Date() }
        return dateFormatter.date(from: str) ?? Date()
    }

    private func summarizeToolInput(name: String, input: [String: Any]?) -> String {
        guard let input else { return "" }

        // Common tool input summaries
        switch name {
        case "Read":
            return (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        case "Write":
            return (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        case "Edit":
            return (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        case "Bash":
            let cmd = input["command"] as? String ?? ""
            return String(cmd.prefix(60))
        case "Glob":
            return input["pattern"] as? String ?? ""
        case "Grep":
            return input["pattern"] as? String ?? ""
        case "WebSearch":
            return input["query"] as? String ?? ""
        default:
            // For unknown tools, show first string value
            for (_, value) in input {
                if let str = value as? String, !str.isEmpty {
                    return String(str.prefix(60))
                }
            }
            return ""
        }
    }
}

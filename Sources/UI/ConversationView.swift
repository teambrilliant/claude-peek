import SwiftUI

struct ConversationView: View {
    let session: SessionState
    @StateObject private var loader = ConversationLoader()
    @ObservedObject private var channel = ChannelClient.shared
    @State private var replyText = ""
    @State private var isSending = false

    private var channelAvailable: Bool {
        channel.isAvailable(cwd: session.cwd)
    }

    private var canReply: Bool {
        channelAvailable && session.phase == .waitingForInput && !isSending
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(session.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                phaseTag
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()
                .background(Color.white.opacity(0.1))

            // Messages
            if loader.messages.isEmpty {
                Spacer()
                Text("No conversation data")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(loader.messages) { message in
                                MessageView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: loader.messages.count) { _, _ in
                        if let lastId = loader.messages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                    .onAppear {
                        if let lastId = loader.messages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            // Reply input — only when channel is available for this session
            if channelAvailable {
                Divider()
                    .background(Color.white.opacity(0.1))

                replyInput
            }
        }
        .onAppear { loader.load(session: session) }
        .onChange(of: session.sessionId) { _, _ in loader.load(session: session) }
        .onDisappear { loader.stop() }
    }

    // MARK: - Reply Input

    @ViewBuilder
    private var replyInput: some View {
        HStack(spacing: 8) {
            TextField("Reply...", text: $replyText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .disabled(!canReply)
                .onSubmit { sendReply() }

            if isSending {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    sendReply()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(canReply && !replyText.isEmpty ? .white : .white.opacity(0.2))
                }
                .buttonStyle(.plain)
                .disabled(!canReply || replyText.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(canReply ? 1 : 0.5)
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canReply else { return }

        replyText = ""
        isSending = true

        Task {
            _ = await ChannelClient.shared.sendReply(text: text, sessionId: session.sessionId, cwd: session.cwd)
            isSending = false
        }
    }

    @ViewBuilder
    private var phaseTag: some View {
        let (label, color) = phaseInfo(session.phase)
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func phaseInfo(_ phase: SessionPhase) -> (String, Color) {
        switch phase {
        case .processing: ("Processing", Color(red: 0.85, green: 0.47, blue: 0.34))
        case .waitingForInput: ("Done", .green)
        case .waitingForApproval: ("Approval", Color(red: 0.95, green: 0.68, blue: 0.0))
        case .compacting: ("Compacting", Color(red: 0.85, green: 0.47, blue: 0.34))
        case .idle: ("Idle", .white.opacity(0.4))
        case .ended: ("Ended", .white.opacity(0.3))
        }
    }
}

// MARK: - Conversation Loader

@MainActor
private final class ConversationLoader: ObservableObject {
    @Published var messages: [ConversationMessage] = []

    private let parser = ConversationParser()
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var fileHandle: FileHandle?
    private var currentFile: URL?

    func load(session: SessionState) {
        stop()

        guard let file = SessionFileMapper.jsonlPath(cwd: session.cwd, sessionId: session.sessionId)
        else { return }

        startWatching(file: file)
    }

    func stop() {
        fileWatcher?.cancel()
        fileWatcher = nil
        try? fileHandle?.close()
        fileHandle = nil
        currentFile = nil
    }

    private func startWatching(file: URL) {
        currentFile = file
        parser.reset()
        messages = parser.parse(file: file)

        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        fileHandle = handle

        let fd = handle.fileDescriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self, let file = self.currentFile else { return }
            self.messages = self.parser.parseIncremental(file: file)
        }

        source.setCancelHandler { [weak self] in
            try? self?.fileHandle?.close()
            self?.fileHandle = nil
        }

        source.resume()
        fileWatcher = source
    }
}

// MARK: - Message View

private struct MessageView: View {
    let message: ConversationMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(message.content.enumerated()), id: \.offset) { _, content in
                switch content {
                case .text(let text):
                    textBlock(text, role: message.role)
                case .toolUse(let tool):
                    toolCallBlock(tool)
                case .thinking(let text):
                    thinkingBlock(text)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(message.role == .user ? Color.white.opacity(0.08) : Color.clear)
        )
    }

    @ViewBuilder
    private func textBlock(_ text: String, role: ConversationRole) -> some View {
        if role == .user {
            Text(stripInternalTags(text))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.9))
                .textSelection(.enabled)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(markdownAttributed(text))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.75))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func toolCallBlock(_ tool: ToolCallInfo) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "terminal")
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.35))

            Text(tool.name)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))

            if !tool.inputSummary.isEmpty {
                Text(tool.inputSummary)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func thinkingBlock(_ text: String) -> some View {
        DisclosureGroup {
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "brain")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.25))
                Text("Thinking")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.25))
            }
        }
        .tint(.white.opacity(0.3))
    }

    // MARK: - Text Processing

    /// Strip Claude Code internal XML tags from user messages
    private func stripInternalTags(_ text: String) -> String {
        var result = text
        // Remove known internal tags and their content
        let contentTags = [
            "local-command-caveat", "system-reminder",
            "bash-stderr",
        ]
        for tag in contentTags {
            let pattern = "<\(tag)>.*?</\(tag)>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) {
                result = regex.stringByReplacingMatches(
                    in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }

        // Format bash input/output blocks as clean text
        if let regex = try? NSRegularExpression(
            pattern: "<bash-input>(.*?)</bash-input>", options: .dotMatchesLineSeparators)
        {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$ $1")
        }
        if let regex = try? NSRegularExpression(
            pattern: "<bash-stdout>(.*?)</bash-stdout>", options: .dotMatchesLineSeparators)
        {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1")
        }

        // Strip any remaining XML-like tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Clean up excess whitespace
        result = result.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Convert markdown to AttributedString for basic rendering
    private func markdownAttributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        ))) ?? AttributedString(text)
    }
}

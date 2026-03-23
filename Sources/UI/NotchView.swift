import SwiftUI

private let cornerRadii = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)

struct NotchView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var sessionManager: SessionManager = .shared

    @State private var previousPendingIds: Set<String> = []
    @State private var isBouncing = false
    @State private var isHovering = false

    private var sessions: [SessionState] {
        sessionManager.activeSessions
    }

    private var isAnyProcessing: Bool {
        sessions.contains { $0.phase.isActive }
    }

    private var hasPendingPermission: Bool {
        sessions.contains { $0.phase.isWaitingForApproval }
    }

    private var hasWaitingForInput: Bool {
        sessions.contains { $0.phase == .waitingForInput }
    }

    private var showClosedActivity: Bool {
        isAnyProcessing || hasPendingPermission || hasWaitingForInput
    }

    private var pillHidden: Bool {
        !viewModel.hasPhysicalNotch && !showClosedActivity && viewModel.status == .closed
    }

    // MARK: - Sizing

    private var closedNotchSize: CGSize {
        CGSize(
            width: viewModel.geometry.deviceNotchRect.width,
            height: viewModel.geometry.deviceNotchRect.height
        )
    }

    private var expansionWidth: CGFloat {
        guard showClosedActivity else { return 0 }
        let permissionExtra: CGFloat = hasPendingPermission ? 18 : 0
        return 2 * max(0, closedNotchSize.height - 12) + 20 + permissionExtra
    }

    private var notchSize: CGSize {
        switch viewModel.status {
        case .closed, .popping: closedNotchSize
        case .opened: viewModel.openedSize
        }
    }

    private var topCornerRadius: CGFloat {
        if !viewModel.hasPhysicalNotch {
            return bottomCornerRadius
        }
        return viewModel.status == .opened ? cornerRadii.opened.top : cornerRadii.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        viewModel.status == .opened ? cornerRadii.opened.bottom : cornerRadii.closed.bottom
    }

    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0)

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                notchLayout
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        alignment: .top
                    )
                    .padding(.horizontal, viewModel.status == .opened ? cornerRadii.opened.top : cornerRadii.closed.bottom)
                    .padding([.horizontal, .bottom], viewModel.status == .opened ? 12 : 0)
                    .background(.black)
                    .clipShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius))
                    .overlay(alignment: .top) {
                        if viewModel.hasPhysicalNotch {
                            Rectangle()
                                .fill(.black)
                                .frame(height: 1)
                                .padding(.horizontal, topCornerRadius)
                        }
                    }
                    .shadow(
                        color: (viewModel.status == .opened || isHovering) ? .black.opacity(0.7) : .clear,
                        radius: 6
                    )
                    .frame(
                        maxWidth: viewModel.status == .opened ? notchSize.width : nil,
                        maxHeight: viewModel.status == .opened ? notchSize.height : nil,
                        alignment: .top
                    )
                    .animation(viewModel.status == .opened ? openAnimation : closeAnimation, value: viewModel.status)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.selectedSessionId)
                    .animation(.smooth, value: showClosedActivity)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isBouncing)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                            isHovering = hovering
                        }
                    }
                    .onTapGesture {
                        if viewModel.status != .opened {
                            viewModel.notchOpen(reason: .click)
                        }
                    }
                    .opacity(pillHidden ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: pillHidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .onChange(of: sessionManager.pendingSessions.map(\.sessionId)) { _, newIds in
            let currentIds = Set(newIds)
            let newPendingIds = currentIds.subtracting(previousPendingIds)
            if !newPendingIds.isEmpty && viewModel.status == .closed {
                viewModel.notchOpen(reason: .notification)
            }
            previousPendingIds = currentIds
        }
        .onChange(of: sessions.map(\.phase)) { _, _ in
            handleWaitingForInputBounce()
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var notchLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .frame(height: max(24, closedNotchSize.height))

            if viewModel.status == .opened {
                HStack(spacing: 0) {
                    sessionListView
                        .frame(width: viewModel.selectedSessionId != nil ? 180 : nil)

                    if let selectedId = viewModel.selectedSessionId,
                        let session = sessionManager.sessions[selectedId]
                    {
                        Divider()
                            .background(Color.white.opacity(0.1))

                        ConversationView(session: session)
                            .id(selectedId)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.selectedSessionId)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.8, anchor: .top)
                            .combined(with: .opacity)
                            .animation(.smooth(duration: 0.35)),
                        removal: .opacity.animation(.easeOut(duration: 0.15))
                    )
                )
            }
        }
    }

    // MARK: - Header Row

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 0) {
            if showClosedActivity {
                HStack(spacing: 4) {
                    closedLeftIndicator
                }
                .frame(width: viewModel.status == .opened ? nil : sideWidth + (hasPendingPermission ? 18 : 0))
                .padding(.leading, viewModel.status == .opened ? 8 : 0)
            }

            if viewModel.status == .opened {
                Spacer()
            } else if !showClosedActivity {
                Rectangle()
                    .fill(.clear)
                    .frame(width: closedNotchSize.width - 20)
            } else {
                Rectangle()
                    .fill(.black)
                    .frame(width: closedNotchSize.width - cornerRadii.closed.top + (isBouncing ? 16 : 0))
            }

            if showClosedActivity && viewModel.status != .opened {
                closedRightIndicator
                    .frame(width: sideWidth)
            }
        }
        .frame(height: closedNotchSize.height)
    }

    private var sideWidth: CGFloat {
        max(0, closedNotchSize.height - 12) + 10
    }

    @ViewBuilder
    private var closedLeftIndicator: some View {
        if hasPendingPermission {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(red: 0.85, green: 0.47, blue: 0.34))
        } else if isAnyProcessing {
            ProcessingDots()
        } else {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
        }
    }

    @ViewBuilder
    private var closedRightIndicator: some View {
        if isAnyProcessing || hasPendingPermission {
            ProcessingDots()
        } else if hasWaitingForInput {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.green)
        }
    }

    // MARK: - Session List (Opened)

    @ViewBuilder
    private var sessionListView: some View {
        if sessions.isEmpty {
            VStack(spacing: 8) {
                Text("No sessions")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                Text("Run claude in terminal")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.25))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(sortedSessions) { session in
                        SessionRow(
                            session: session,
                            isSelected: viewModel.selectedSessionId == session.sessionId,
                            onSelect: { viewModel.selectSession(session.sessionId) }
                        )
                        .id(session.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var sortedSessions: [SessionState] {
        sessions.sorted { a, b in
            let priorityA = phasePriority(a.phase)
            let priorityB = phasePriority(b.phase)
            if priorityA != priorityB { return priorityA < priorityB }
            return a.lastActivity > b.lastActivity
        }
    }

    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .processing, .compacting: 0
        case .waitingForInput: 1
        case .idle, .ended: 2
        }
    }

    private func handleWaitingForInputBounce() {
        let waitingIds = Set(sessions.filter { $0.phase == .waitingForInput }.map(\.id))
        let newlyWaiting = waitingIds.subtracting(previousPendingIds)
        if !newlyWaiting.isEmpty {
            isBouncing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isBouncing = false
            }
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let session: SessionState
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovered = false
    @State private var spinnerPhase = 0

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let spinnerTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            stateIndicator
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if session.phase.isWaitingForApproval, let toolName = session.phase.approvalToolName {
                    HStack(spacing: 4) {
                        Text(toolName)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(red: 0.95, green: 0.68, blue: 0.0).opacity(0.9))
                        if let input = session.activePermission?.formattedInput {
                            Text(input)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text(phaseLabel)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer(minLength: 0)

            if isHovered, let pid = session.pid {
                Button {
                    TerminalFocuser.focusTerminal(claudePid: pid)
                } label: {
                    Image(systemName: "terminal")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            if session.phase.isWaitingForApproval {
                approvalButtons
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.white.opacity(0.1) : isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: session.phase.isWaitingForApproval)
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch session.phase {
        case .processing, .compacting:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(claudeOrange)
                .onReceive(spinnerTimer) { _ in spinnerPhase += 1 }
        case .waitingForApproval:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(red: 0.95, green: 0.68, blue: 0.0))
                .onReceive(spinnerTimer) { _ in spinnerPhase += 1 }
        case .waitingForInput:
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
        case .idle, .ended:
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
        }
    }

    private var phaseLabel: String {
        switch session.phase {
        case .idle: "Idle"
        case .processing: "Processing..."
        case .waitingForInput: "Done"
        case .waitingForApproval: "Waiting for approval"
        case .compacting: "Compacting..."
        case .ended: "Ended"
        }
    }

    @ViewBuilder
    private var approvalButtons: some View {
        HStack(spacing: 6) {
            Button {
                SessionManager.shared.denyPermission(sessionId: session.sessionId, reason: nil)
            } label: {
                Text("Deny")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                SessionManager.shared.approvePermission(sessionId: session.sessionId)
            } label: {
                Text("Allow")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                SessionManager.shared.approvePermissionAlways(sessionId: session.sessionId)
            } label: {
                Text("Always")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.85))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Processing Dots

private struct ProcessingDots: View {
    @State private var phase = 0
    private let symbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(symbols[phase % symbols.count])
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(Color(red: 0.85, green: 0.47, blue: 0.34))
            .onReceive(timer) { _ in phase += 1 }
    }
}

import AppKit
import Combine
import SwiftUI

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason {
    case click
    case hover
    case notification
    case boot
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var status: NotchStatus = .closed
    @Published private(set) var openReason: NotchOpenReason = .boot
    @Published var isHovering: Bool = false
    @Published var selectedSessionId: String?

    @Published var geometry: NotchGeometry
    @Published var hasPhysicalNotch: Bool

    var openedSize: CGSize {
        if selectedSessionId != nil {
            return CGSize(
                width: min(geometry.screenRect.width * 0.55, 720),
                height: 440
            )
        }
        return CGSize(
            width: min(geometry.screenRect.width * 0.4, 480),
            height: 320
        )
    }

    func selectSession(_ sessionId: String?) {
        if selectedSessionId == sessionId {
            selectedSessionId = nil
        } else {
            selectedSessionId = sessionId
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: DispatchWorkItem?
    private var mouseMovedMonitor: Any?
    private var mouseDownMonitor: Any?
    private var localMouseDownMonitor: Any?

    private let screenTracker: ActiveScreenTracker

    init(geometry: NotchGeometry, hasPhysicalNotch: Bool, screenTracker: ActiveScreenTracker) {
        self.geometry = geometry
        self.hasPhysicalNotch = hasPhysicalNotch
        self.screenTracker = screenTracker
        setupEventMonitors()
        observeSessionManager()
    }

    deinit {
        if let monitor = mouseMovedMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = mouseDownMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMouseDownMonitor { NSEvent.removeMonitor(monitor) }
    }

    // MARK: - Actions

    func notchOpen(reason: NotchOpenReason) {
        openReason = reason
        status = .opened
    }

    func notchClose() {
        status = .closed
        selectedSessionId = nil
    }

    // MARK: - Setup

    private func setupEventMonitors() {
        mouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) {
            [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleMouseMove(NSEvent.mouseLocation)
                if self.status != .opened {
                    self.screenTracker.handleMouseMoved()
                }
            }
        }

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleMouseDown()
            }
        }

        // Local monitor catches clicks on our own window (the transparent area
        // outside the panel content) — global monitor only fires for other apps
        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            guard let self else { return event }
            Task { @MainActor in
                self.handleMouseDown()
            }
            return event
        }
    }

    private func observeSessionManager() {
        SessionManager.shared.$sessions
            .map { sessions in sessions.values.contains { $0.phase.isWaitingForApproval } }
            .removeDuplicates()
            .sink { [weak self] hasPending in
                guard let self else { return }
                if hasPending && self.status == .closed {
                    self.notchOpen(reason: .notification)
                } else if !hasPending && self.status == .opened && self.openReason == .notification {
                    self.notchClose()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Mouse Handling

    private func handleMouseMove(_ location: CGPoint) {
        let inNotch = geometry.isPointInNotch(location)
        let inOpened =
            status == .opened && geometry.isPointInOpenedPanel(location, size: openedSize)

        let newHovering = inNotch || inOpened
        guard newHovering != isHovering else { return }
        isHovering = newHovering

        hoverTimer?.cancel()
        hoverTimer = nil

        if isHovering && status == .closed {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.isHovering else { return }
                self.notchOpen(reason: .hover)
            }
            hoverTimer = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
        }
    }

    private func handleMouseDown() {
        let location = NSEvent.mouseLocation

        switch status {
        case .opened:
            if geometry.isPointOutsidePanel(location, size: openedSize) {
                notchClose()
            }
        case .closed, .popping:
            if geometry.isPointInNotch(location) {
                notchOpen(reason: .click)
            }
        }
    }

    func performBootAnimation() {
        notchOpen(reason: .boot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.openReason == .boot else { return }
            self.notchClose()
        }
    }
}

import AppKit
import Combine
import SwiftUI

// MARK: - NotchPanel

class NotchPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        hasShadow = false
        isMovable = false

        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]

        level = .mainMenu + 3
        allowsToolTipsWhenApplicationIsInactive = true
        ignoresMouseEvents = true
        isReleasedWhenClosed = true
        acceptsMouseMovedEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - NotchWindowController

class NotchWindowController: NSWindowController {
    let viewModel: NotchViewModel
    private let screen: NSScreen
    private var cancellables = Set<AnyCancellable>()

    init(screen: NSScreen, screenTracker: ActiveScreenTracker) {
        self.screen = screen

        let screenFrame = screen.frame
        let notchSize = screen.notchSize
        let windowHeight: CGFloat = 500

        let windowFrame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )

        let deviceNotchRect = CGRect(
            x: (screenFrame.width - notchSize.width) / 2,
            y: 0,
            width: notchSize.width,
            height: notchSize.height
        )

        let geometry = NotchGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenFrame,
            windowHeight: windowHeight
        )

        self.viewModel = NotchViewModel(
            geometry: geometry,
            hasPhysicalNotch: screen.hasPhysicalNotch,
            screenTracker: screenTracker
        )

        let panel = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: panel)

        let notchView = NotchView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: notchView)
        hostingView.frame = windowFrame
        panel.contentView = hostingView

        panel.setFrame(windowFrame, display: true)

        // Toggle mouse event handling based on notch state
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak panel] status in
                switch status {
                case .opened:
                    // Accept mouse events so buttons work, but never steal focus
                    panel?.ignoresMouseEvents = false
                case .closed, .popping:
                    panel?.ignoresMouseEvents = true
                }
            }
            .store(in: &cancellables)

        panel.ignoresMouseEvents = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.viewModel.performBootAnimation()
        }
    }

    func relocate(to screen: NSScreen) {
        let screenFrame = screen.frame
        let notchSize = screen.notchSize
        let windowHeight: CGFloat = 500

        let windowFrame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )

        let deviceNotchRect = CGRect(
            x: (screenFrame.width - notchSize.width) / 2,
            y: 0,
            width: notchSize.width,
            height: notchSize.height
        )

        let geometry = NotchGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenFrame,
            windowHeight: windowHeight
        )

        viewModel.geometry = geometry
        viewModel.hasPhysicalNotch = screen.hasPhysicalNotch

        guard let panel = window else { return }
        panel.setFrame(windowFrame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: windowFrame.size)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

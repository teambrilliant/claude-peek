import AppKit
import Combine
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NotchWindowController?
    private let screenTracker = ActiveScreenTracker()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        SessionManager.shared.startListening()
        setupWindow()

        screenTracker.$activeScreen
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] screen in
                self?.windowController?.relocate(to: screen)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenDidChange() {
        screenTracker.revalidate()
        windowController?.relocate(to: screenTracker.activeScreen)
    }

    private func setupWindow() {
        if let existing = windowController {
            existing.window?.orderOut(nil)
            existing.window?.close()
            windowController = nil
        }

        let screen = screenTracker.activeScreen
        windowController = NotchWindowController(screen: screen, screenTracker: screenTracker)
        windowController?.showWindow(nil)
    }
}

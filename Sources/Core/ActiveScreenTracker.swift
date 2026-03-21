import AppKit
import Combine

@MainActor
final class ActiveScreenTracker: ObservableObject {
    @Published private(set) var activeScreen: NSScreen

    private var debounceWork: DispatchWorkItem?
    private var pendingScreen: NSScreen?

    init() {
        self.activeScreen = Self.screenForMouse() ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func handleMouseMoved() {
        guard let screen = Self.screenForMouse(),
              screen != activeScreen
        else {
            // Mouse still on same screen — cancel any pending switch
            if pendingScreen != nil {
                debounceWork?.cancel()
                pendingScreen = nil
            }
            return
        }

        guard screen != pendingScreen else { return }
        pendingScreen = screen

        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let pending = self.pendingScreen else { return }
            self.activeScreen = pending
            self.pendingScreen = nil
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func revalidate() {
        // Called when screen configuration changes (display connected/disconnected)
        let current = Self.screenForMouse() ?? NSScreen.main ?? NSScreen.screens[0]
        debounceWork?.cancel()
        pendingScreen = nil
        activeScreen = current
    }

    private static func screenForMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }
}

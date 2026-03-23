import AppKit
import os.log

private let logger = Logger(subsystem: "com.teambrilliant.claude-peek", category: "TerminalFocus")

enum TerminalFocuser {
    private static let terminalBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "dev.zed.Zed",
        "net.kovidgoyal.kitty",
        "org.alacritty",
    ]

    /// Focus the terminal window running a Claude session
    static func focusTerminal(claudePid: Int, cwd: String) {
        guard let terminalPid = findTerminalPid(childPid: claudePid) else { return }

        let apps = NSWorkspace.shared.runningApplications
        guard let app = apps.first(where: { $0.processIdentifier == terminalPid }) else { return }

        // With accessibility permission, raise the specific window matching the project
        if AXIsProcessTrusted() {
            raiseMatchingWindow(pid: terminalPid, cwd: cwd)
        }

        app.activate()
    }

    /// Prompt for accessibility permission if not granted
    static func requestAccessibilityIfNeeded() {
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    // MARK: - Window Matching

    private static func raiseMatchingWindow(pid: pid_t, cwd: String) {
        let appRef = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef) == .success,
            let windows = windowsRef as? [AXUIElement]
        else { return }

        let projectName = URL(fileURLWithPath: cwd).lastPathComponent

        for window in windows {
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                let title = titleRef as? String
            else { continue }

            if title.contains(projectName) {
                focusWindow(window)
                return
            }
        }

        if let firstWindow = windows.first {
            focusWindow(firstWindow)
        }
    }

    private static func focusWindow(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFTypeRef)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, true as CFTypeRef)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    // MARK: - PID Walking

    private static func findTerminalPid(childPid: Int) -> pid_t? {
        var pid = childPid

        for _ in 0..<10 {
            let parent = parentPid(of: pid)
            guard parent > 1 else { return nil }

            if let app = NSWorkspace.shared.runningApplications.first(
                where: { $0.processIdentifier == parent })
            {
                if let bundleId = app.bundleIdentifier,
                    terminalBundleIds.contains(bundleId)
                {
                    return parent
                }
            }

            pid = Int(parent)
        }

        return nil
    }

    private static func parentPid(of pid: Int) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]

        let result = sysctl(&mib, 4, &info, &size, nil, 0)
        guard result == 0 else { return 0 }

        return info.kp_eproc.e_ppid
    }
}

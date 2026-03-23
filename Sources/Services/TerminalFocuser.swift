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

        if AXIsProcessTrusted() {
            // Raise the matching window — this triggers macOS Space switch
            raiseMatchingWindow(pid: terminalPid, cwd: cwd)
            // Delay activate so the Space switch completes first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                app.activate()
            }
        } else {
            app.activate()
        }
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
        // Set as main window — on some apps this triggers Space switch
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFTypeRef)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, true as CFTypeRef)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)

        // Get window title for AppleScript fallback
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        if let title = titleRef as? String, !title.isEmpty {
            raiseWindowViaAppleScript(windowTitle: title)
        }
    }

    /// AppleScript can switch Spaces — AXRaise alone often can't
    private static func raiseWindowViaAppleScript(windowTitle: String) {
        let escaped = windowTitle.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
            tell application "System Events"
                set targetWindow to missing value
                repeat with proc in (every process whose background only is false)
                    try
                        repeat with w in (every window of proc)
                            if name of w contains "\(escaped)" then
                                set targetWindow to w
                                perform action "AXRaise" of targetWindow
                                set frontmost of proc to true
                                return
                            end if
                        end repeat
                    end try
                end repeat
            end tell
            """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
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

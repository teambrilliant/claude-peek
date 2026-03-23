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

    /// Focus the terminal app running a Claude session with the given PID
    static func focusTerminal(claudePid: Int) {
        // Walk parent chain to find the terminal app
        guard let terminalPid = findTerminalPid(childPid: claudePid) else {
            logger.debug("No terminal app found for PID \(claudePid)")
            return
        }

        // Find and activate the running application
        let apps = NSWorkspace.shared.runningApplications
        guard let app = apps.first(where: { $0.processIdentifier == terminalPid }) else {
            logger.debug("No running app for terminal PID \(terminalPid)")
            return
        }

        app.activate()
        logger.info("Focused \(app.localizedName ?? "terminal", privacy: .public) for Claude PID \(claudePid)")
    }

    private static func findTerminalPid(childPid: Int) -> pid_t? {
        var pid = childPid

        for _ in 0..<10 {
            let parent = parentPid(of: pid)
            guard parent > 1 else { return nil }

            // Check if this parent is a known terminal app
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

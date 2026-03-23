import AppKit

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

    /// Focus the terminal running a Claude session.
    /// Opens the project directory with the owning terminal app — macOS handles
    /// the Space switch. IDE apps (Zed, VS Code) focus the existing project window.
    static func focusTerminal(claudePid: Int, cwd: String) {
        guard let terminalPid = findTerminalPid(childPid: claudePid) else { return }

        let apps = NSWorkspace.shared.runningApplications
        guard let app = apps.first(where: { $0.processIdentifier == terminalPid }),
            let bundleURL = app.bundleURL
        else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        NSWorkspace.shared.open(
            [URL(fileURLWithPath: cwd)],
            withApplicationAt: bundleURL,
            configuration: config
        )
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

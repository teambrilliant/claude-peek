import AppKit

extension NSScreen {
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(width: 80, height: 24)
        }

        let notchHeight = safeAreaInsets.top
        let fullWidth = frame.width
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0

        guard leftPadding > 0, rightPadding > 0 else {
            return CGSize(width: 180, height: notchHeight)
        }

        let notchWidth = fullWidth - leftPadding - rightPadding + 4
        return CGSize(width: notchWidth, height: notchHeight)
    }

    var hasPhysicalNotch: Bool {
        safeAreaInsets.top > 0
    }

    var isBuiltinDisplay: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    static var builtin: NSScreen? {
        screens.first(where: { $0.isBuiltinDisplay }) ?? NSScreen.main
    }
}

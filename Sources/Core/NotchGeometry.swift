import CoreGraphics

struct NotchGeometry: Sendable {
    let deviceNotchRect: CGRect
    let screenRect: CGRect
    let windowHeight: CGFloat

    var notchScreenRect: CGRect {
        CGRect(
            x: screenRect.midX - deviceNotchRect.width / 2,
            y: screenRect.maxY - deviceNotchRect.height,
            width: deviceNotchRect.width,
            height: deviceNotchRect.height
        )
    }

    func openedScreenRect(for size: CGSize) -> CGRect {
        let width = size.width - 6
        let height = size.height - 30
        return CGRect(
            x: screenRect.midX - width / 2,
            y: screenRect.maxY - height,
            width: width,
            height: height
        )
    }

    /// Hit area for the closed notch — extends well beyond the device notch
    /// to cover expanded indicators (spinner, green dot, etc)
    func isPointInNotch(_ point: CGPoint) -> Bool {
        let expandedRect = notchScreenRect.insetBy(dx: -40, dy: -5)
        return expandedRect.contains(point)
    }

    func isPointInOpenedPanel(_ point: CGPoint, size: CGSize) -> Bool {
        // Use full size centered at top of screen (no insets — match visual bounds)
        let rect = CGRect(
            x: screenRect.midX - size.width / 2,
            y: screenRect.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return rect.contains(point)
    }

    func isPointOutsidePanel(_ point: CGPoint, size: CGSize) -> Bool {
        !isPointInOpenedPanel(point, size: size)
    }
}

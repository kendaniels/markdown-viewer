import AppKit
import SwiftUI

private enum WindowSizePersistence {
    static let minSize = NSSize(width: 720, height: 480)

    private static let widthKey = "windowFrameWidth"
    private static let heightKey = "windowFrameHeight"

    static var savedSize: NSSize? {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: widthKey)
        let height = defaults.double(forKey: heightKey)

        guard width > 0, height > 0 else {
            return nil
        }

        return NSSize(
            width: max(width, minSize.width),
            height: max(height, minSize.height)
        )
    }

    static func save(_ size: NSSize) {
        let defaults = UserDefaults.standard
        defaults.set(max(size.width, minSize.width), forKey: widthKey)
        defaults.set(max(size.height, minSize.height), forKey: heightKey)
    }
}

struct WindowSizeTrackingView: NSViewRepresentable {
    func makeNSView(context: Context) -> TrackingNSView {
        TrackingNSView()
    }

    func updateNSView(_ nsView: TrackingNSView, context: Context) {
        nsView.attachIfNeeded()
    }
}

final class TrackingNSView: NSView {
    private weak var observedWindow: NSWindow?
    private var resizeObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private var appliedSizeToCurrentWindow = false

    deinit {
        removeObservers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfNeeded()
    }

    func attachIfNeeded() {
        guard let window, window !== observedWindow else {
            return
        }

        removeObservers()
        observedWindow = window
        appliedSizeToCurrentWindow = false

        applySavedSize(to: window)

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let resizedWindow = notification.object as? NSWindow else {
                return
            }

            WindowSizePersistence.save(resizedWindow.frame.size)
            self?.observedWindow = resizedWindow
        }

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.removeObservers()
            self?.observedWindow = nil
        }
    }

    private func applySavedSize(to window: NSWindow) {
        guard !appliedSizeToCurrentWindow, let savedSize = WindowSizePersistence.savedSize else {
            return
        }

        var frame = window.frame
        frame.size = savedSize
        window.setFrame(frame, display: true)
        appliedSizeToCurrentWindow = true
    }

    private func removeObservers() {
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }

        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
    }
}

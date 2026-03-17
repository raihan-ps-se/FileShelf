import Cocoa

class ShelfWindow: NSPanel {
    private(set) var shelfView: ShelfView!

    init() {
        let rect = NSRect(x: 0, y: 0, width: 140, height: 110)
        super.init(
            contentRect: rect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .modalPanel   // above Electron/Chromium floating windows
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        acceptsMouseMovedEvents = true

        shelfView = ShelfView(frame: NSRect(origin: .zero, size: rect.size))
        contentView = shelfView

        restorePosition()
    }

    // MARK: - Position

    private func restorePosition() {
        if let saved = UserDefaults.standard.string(forKey: "shelfOrigin") {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                setFrameOrigin(NSPoint(x: parts[0], y: parts[1]))
                return
            }
        }
        // Default: right edge of screen, vertically centered
        guard let screen = NSScreen.main else { return }
        let x = screen.visibleFrame.maxX - 150
        let y = screen.visibleFrame.midY - 55
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func savePosition() {
        let o = frame.origin
        UserDefaults.standard.set("\(o.x),\(o.y)", forKey: "shelfOrigin")
    }

    // MARK: - Show / Hide

    func showAnimated() {
        guard !isVisible else { return }
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            animator().alphaValue = 1.0
        }
    }

    func hideAnimated() {
        savePosition()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.alphaValue = 1.0
        })
    }

    func addFilesAndShow(_ urls: [URL]) {
        shelfView.addFiles(urls)
        showAnimated()
    }

    // MARK: - Overrides

    // Don't quit on close — just hide
    override func close() {
        hideAnimated()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

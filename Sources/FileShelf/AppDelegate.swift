import Cocoa
import ServiceManagement
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var shelfWindow: ShelfWindow!
    private var statusItem: NSStatusItem!

    // Global event monitors
    private var monitors: [Any] = []

    // Cmd+C hold state
    private var cmdCTimer: Timer?
    private var cmdCHeld = false

    // Drag hold state
    private var dragStartTime: Date?
    private var dragTriggered = false
    private var dragPasteboardChangeCount = 0

    // Carbon global hotkey (⌥Space — works without Accessibility permission)
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        shelfWindow = ShelfWindow()
        setupStatusBar()
        promptAccessibilityPermission()
        setupMonitors()
        setupGlobalHotKey()
    }

    // MARK: - Global Hotkey (⌥Space via Carbon — no Accessibility needed)

    private func setupGlobalHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    if delegate.shelfWindow.isVisible { delegate.shelfWindow.hideAnimated() }
                    else                              { delegate.shelfWindow.showAnimated()  }
                }
                return noErr
            },
            1, &eventType, userData, &hotKeyEventHandlerRef
        )
        var keyID = EventHotKeyID()
        keyID.signature = 0x46534C54   // "FSLT"
        keyID.id = 1
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), keyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "tray.fill", accessibilityDescription: "FileShelf")
        button.action = #selector(toggleShelf)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
    }

    @objc private func toggleShelf() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            if shelfWindow.isVisible {
                shelfWindow.hideAnimated()
            } else {
                shelfWindow.showAnimated()
            }
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: shelfWindow.isVisible ? "Hide Shelf" : "Show Shelf",
            action: #selector(toggleShelfFromMenu),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let clear = NSMenuItem(title: "Clear Files", action: #selector(clearShelfFiles), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        launchItem.target = self
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit FileShelf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil   // remove so left-click still works normally next time
    }

    @objc private func toggleShelfFromMenu() {
        if shelfWindow.isVisible {
            shelfWindow.hideAnimated()
        } else {
            shelfWindow.showAnimated()
        }
    }

    @objc private func clearShelfFiles() {
        shelfWindow.shelfView.clearAll()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at Login"
            alert.informativeText = "Could not update setting: \(error.localizedDescription)\n\nMove FileShelf.app to your Applications folder and try again."
            alert.runModal()
        }
    }

    // MARK: - Accessibility Permission

    private func promptAccessibilityPermission() {
        guard !AXIsProcessTrusted() else { return }
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Global Monitors (Accessibility required for keyboard events)

    private func setupMonitors() {
        func add(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
                monitors.append(m)
            }
        }

        // Cmd+C hold (requires Accessibility permission)
        add(.keyDown)      { [weak self] in self?.onKeyDown($0) }
        add(.keyUp)        { [weak self] in self?.onKeyUp($0) }
        add(.flagsChanged) { [weak self] in self?.onFlagsChanged($0) }

        // Mouse: drag hold detection (no special permission needed)
        add(.leftMouseDown)    { [weak self] _ in
            self?.dragStartTime = nil
            self?.dragTriggered = false
            self?.dragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        }
        add(.leftMouseDragged) { [weak self] _ in self?.onMouseDragged() }
        add(.leftMouseUp)      { [weak self] _ in self?.dragStartTime = nil; self?.dragTriggered = false }
    }

    // MARK: - Cmd+C Hold → show shelf + auto-add clipboard file

    private func onKeyDown(_ event: NSEvent) {
        // Cmd+C hold (3 s) → show shelf + add clipboard file
        guard event.keyCode == 8,
              event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.shift),
              !event.modifierFlags.contains(.option),
              !event.modifierFlags.contains(.control),
              !cmdCHeld
        else { return }

        cmdCHeld = true
        cmdCTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.triggerFromClipboard() }
        }
    }

    private func onKeyUp(_ event: NSEvent) {
        guard event.keyCode == 8 else { return }
        cmdCHeld = false
        cmdCTimer?.invalidate()
        cmdCTimer = nil
    }

    private func onFlagsChanged(_ event: NSEvent) {
        guard !event.modifierFlags.contains(.command) else { return }
        cmdCHeld = false
        cmdCTimer?.invalidate()
        cmdCTimer = nil
    }

    private func triggerFromClipboard() {
        let pb = NSPasteboard.general
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] ?? []
        if !urls.isEmpty {
            shelfWindow.addFilesAndShow(urls)
        } else {
            shelfWindow.showAnimated()
        }
    }

    // MARK: - Drag Hold → show shelf so user can drop onto it

    private func onMouseDragged() {
        if dragStartTime == nil { dragStartTime = Date() }
        guard !dragTriggered,
              let t = dragStartTime,
              Date().timeIntervalSince(t) >= 1.5
        else { return }

        // Only trigger for file drags:
        // 1. The drag pasteboard must have been updated since mouse-down
        //    (text selection doesn't update the drag pasteboard)
        // 2. It must contain file URL types
        let pb = NSPasteboard(name: .drag)
        guard pb.changeCount > dragPasteboardChangeCount else { return }
        let fileTypes: Set<NSPasteboard.PasteboardType> = [
            .fileURL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ]
        guard let pbTypes = pb.types, !Set(pbTypes).isDisjoint(with: fileTypes) else { return }

        dragTriggered = true
        DispatchQueue.main.async { [weak self] in self?.shelfWindow.showAnimated() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    deinit {
        monitors.forEach { NSEvent.removeMonitor($0) }
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = hotKeyEventHandlerRef { RemoveEventHandler(ref) }
    }
}

import Cocoa
import QuartzCore

class ShelfView: NSView {

    // MARK: - State
    private var storedFiles: [URL] = []
    private var isDragOver = false
    private var isDraggingOut = false
    private var hoveredIndex: Int? = nil
    private var selectedIndices: Set<Int> = []
    private var flashIndices: Set<Int> = []

    private enum ActionButton: Equatable { case compress, airDrop }
    private var hoveredActionButton: ActionButton? = nil
    private var isCompressing = false

    // Local key monitor
    private var localKeyMonitor: Any?

    // MARK: - Layout
    private let slotSize: CGFloat = 82
    private let iconSize: CGFloat = 52
    private let hPad: CGFloat = 8
    private let vPad: CGFloat = 8
    private let dropZoneHeight: CGFloat = 60
    private let actionBarHeight: CGFloat = 38
    private let cornerRadius: CGFloat = 20
    private let maxCols = 3

    private let emptyWidth:  CGFloat = 140
    private let emptyHeight: CGFloat = 110

    private var numCols: Int { min(max(storedFiles.count, 1), maxCols) }
    private var numRows: Int { storedFiles.isEmpty ? 0 : (storedFiles.count + maxCols - 1) / maxCols }
    var viewWidth: CGFloat { max(emptyWidth, hPad + CGFloat(numCols) * slotSize + hPad) }

    // MARK: - Mouse tracking
    private var mouseDownPoint: NSPoint = .zero
    private var mouseDownFileIndex: Int? = nil
    private var didDrag = false
    private var windowDragScreenOrigin: NSPoint = .zero
    private var windowFrameOriginAtDragStart: NSPoint = .zero

    // MARK: - Init
    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("public.url"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        ])
        updateTrackingAreas()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let cmd = event.modifierFlags.contains(.command)
            let plain = !event.modifierFlags.contains(.shift) && !event.modifierFlags.contains(.option)
            if event.keyCode == 0,  cmd, plain { self?.selectAllFiles(); return nil }   // Cmd+A
            if event.keyCode == 12, cmd, plain { NSApp.terminate(nil);   return nil }   // Cmd+Q
            if event.keyCode == 51, cmd, plain {                                        // Cmd+Delete
                if let self, !self.selectedIndices.isEmpty { self.removeSelected() }
                else { self?.clearAll() }
                return nil
            }
            return event
        }
    }

    deinit { if let m = localKeyMonitor { NSEvent.removeMonitor(m) } }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { loadFiles(); updateWindowSize() }
    }

    // MARK: - Persistence

    private func saveFiles() {
        UserDefaults.standard.set(storedFiles.map { $0.path }, forKey: "storedFilePaths")
    }

    private func loadFiles() {
        let paths = UserDefaults.standard.stringArray(forKey: "storedFilePaths") ?? []
        storedFiles = paths.compactMap { path in
            FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
    }

    // MARK: - Tracking areas
    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    // MARK: - Geometry

    var totalHeight: CGFloat {
        let computed = vPad + (storedFiles.isEmpty ? 0 : actionBarHeight) + dropZoneHeight + CGFloat(numRows) * slotSize + vPad
        return max(emptyHeight, computed)
    }

    // Horizontal offset to center the file grid when fewer than maxCols files are present
    private var gridXOffset: CGFloat {
        let naturalW = hPad + CGFloat(numCols) * slotSize + hPad
        return max(0, (viewWidth - naturalW) / 2)
    }

    private func slotRect(for index: Int) -> NSRect {
        let col = index % maxCols
        let row = index / maxCols
        let x = gridXOffset + hPad + CGFloat(col) * slotSize
        let actionH = storedFiles.isEmpty ? 0 : actionBarHeight
        let y = vPad + actionH + dropZoneHeight + CGFloat(numRows - row - 1) * slotSize
        return NSRect(x: x, y: y, width: slotSize, height: slotSize)
    }

    private var dropZoneRect: NSRect {
        if storedFiles.isEmpty {
            return NSRect(x: 0, y: vPad, width: viewWidth, height: totalHeight - 2 * vPad)
        }
        return NSRect(x: 0, y: vPad + actionBarHeight, width: viewWidth, height: dropZoneHeight)
    }

    private var actionBarRect: NSRect {
        NSRect(x: 0, y: vPad, width: viewWidth, height: actionBarHeight)
    }

    private var compressButtonRect: NSRect {
        let size: CGFloat = 24
        return NSRect(x: viewWidth / 4 - size / 2, y: vPad + (actionBarHeight - size) / 2,
                      width: size, height: size)
    }

    private var airDropButtonRect: NSRect {
        let size: CGFloat = 24
        return NSRect(x: 3 * viewWidth / 4 - size / 2, y: vPad + (actionBarHeight - size) / 2,
                      width: size, height: size)
    }

    private func fileIndex(at point: NSPoint) -> Int? {
        for i in 0..<storedFiles.count {
            if slotRect(for: i).insetBy(dx: 3, dy: 3).contains(point) { return i }
        }
        return nil
    }

    private func closeButtonRect(for index: Int) -> NSRect {
        let slot = slotRect(for: index)
        return NSRect(x: slot.maxX - 18, y: slot.maxY - 18, width: 14, height: 14)
    }

    // MARK: - Window resize (top-right corner fixed)
    func updateWindowSize() {
        guard let window = window else { return }
        let newW = viewWidth, newH = totalHeight
        let screen = window.screen ?? NSScreen.main!
        var f = window.frame
        f.origin.y += f.height - newH
        f.origin.x += f.width  - newW
        f.size = CGSize(width: newW, height: newH)
        f.origin.x = max(screen.visibleFrame.minX, min(f.origin.x, screen.visibleFrame.maxX - newW))
        f.origin.y = max(screen.visibleFrame.minY, f.origin.y)
        window.setFrame(f, display: true, animate: false)
        self.frame = NSRect(origin: .zero, size: CGSize(width: newW, height: newH))
        updateTrackingAreas()
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let bgRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let bg = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

        // Gradient fill — subtle top-to-bottom depth
        let topColor = isDragOver ? NSColor(white: 0.22, alpha: 0.97) : NSColor(white: 0.18, alpha: 0.97)
        let botColor = isDragOver ? NSColor(white: 0.13, alpha: 0.97) : NSColor(white: 0.09, alpha: 0.97)
        if let grad = NSGradient(starting: topColor, ending: botColor) {
            grad.draw(in: bg, angle: 90)
        }

        // Border
        let borderColor = isDragOver ? NSColor.systemBlue.withAlphaComponent(0.85)
                                     : NSColor(white: 1, alpha: 0.16)
        borderColor.setStroke()
        bg.lineWidth = isDragOver ? 1.5 : 1.0
        bg.stroke()

        // Inner top highlight for glass feel
        if !isDragOver {
            let hl = NSBezierPath()
            hl.move(to:   NSPoint(x: cornerRadius + 2,          y: bgRect.maxY - 0.5))
            hl.line(to:   NSPoint(x: bgRect.maxX - cornerRadius - 2, y: bgRect.maxY - 0.5))
            NSColor(white: 1, alpha: 0.09).setStroke()
            hl.lineWidth = 1; hl.stroke()
        }

        for i in 0..<storedFiles.count { drawSlot(index: i) }
        drawDropZone()
        drawActionBar()
    }

    private func drawSlot(index: Int) {
        let url = storedFiles[index]
        let rect = slotRect(for: index)
        let isHovered  = hoveredIndex == index
        let isSelected = selectedIndices.contains(index)
        let isFlashing = flashIndices.contains(index)

        let slotPath = NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 3), xRadius: 10, yRadius: 10)
        if isFlashing {
            NSColor.systemBlue.withAlphaComponent(0.45).setFill(); slotPath.fill()
        } else if isSelected {
            NSColor.systemBlue.withAlphaComponent(isHovered ? 0.28 : 0.18).setFill(); slotPath.fill()
            NSColor.systemBlue.withAlphaComponent(0.85).setStroke()
            slotPath.lineWidth = 1.5; slotPath.stroke()
        } else if isHovered {
            NSColor(white: 1, alpha: 0.07).setFill(); slotPath.fill()
        }

        // Icon — vertically centered with room for label below
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let iconX = rect.minX + (slotSize - iconSize) / 2
        let iconY = rect.minY + 16
        icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))

        // Label
        let raw       = url.deletingPathExtension().lastPathComponent
        let name      = raw.count > 9 ? String(raw.prefix(8)) + "…" : raw
        let labelText = isFlashing ? "✓ Copied" : name
        let labelAlpha: CGFloat = isFlashing ? 0.95 : (isSelected ? 0.90 : 0.55)
        let label = NSAttributedString(string: labelText, attributes: [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: NSColor(white: 1, alpha: labelAlpha)
        ])
        let ls = label.size()
        label.draw(at: NSPoint(x: rect.minX + (slotSize - ls.width) / 2, y: rect.minY + 5))

        // X button — red circle on hover
        if isHovered {
            let btn = closeButtonRect(for: index)
            NSColor(red: 0.88, green: 0.25, blue: 0.20, alpha: 0.95).setFill()
            NSBezierPath(ovalIn: btn).fill()
            let x = NSAttributedString(string: "×", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.white
            ])
            let xs = x.size()
            x.draw(at: NSPoint(x: btn.midX - xs.width / 2, y: btn.midY - xs.height / 2))
        }
    }

    private func drawDropZone() {
        let rect = dropZoneRect

        if storedFiles.isEmpty {
            // Large tray icon
            let iconSymbol = isDragOver ? "arrow.down.circle.fill" : "tray.and.arrow.down"
            let iconColor  = isDragOver ? NSColor.systemBlue : NSColor(white: 1, alpha: 0.28)
            let iconCfg = NSImage.SymbolConfiguration(pointSize: 22, weight: .thin)
                .applying(NSImage.SymbolConfiguration(hierarchicalColor: iconColor))
            if let img = NSImage(systemSymbolName: iconSymbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(iconCfg) {
                let s = NSSize(width: 28, height: 28)
                img.draw(in: NSRect(x: rect.midX - s.width / 2,
                                    y: rect.midY,
                                    width: s.width, height: s.height))
            }
            // "Drop files here"
            let primary = NSAttributedString(string: "Drop files here", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor(white: 1, alpha: isDragOver ? 0.85 : 0.38)
            ])
            let ps = primary.size()
            primary.draw(at: NSPoint(x: rect.midX - ps.width / 2, y: rect.midY - ps.height - 4))

            // Hint line
            if !isDragOver {
                let hint = NSAttributedString(string: "⌥Space to toggle", attributes: [
                    .font: NSFont.systemFont(ofSize: 8, weight: .regular),
                    .foregroundColor: NSColor(white: 1, alpha: 0.18)
                ])
                let hs = hint.size()
                hint.draw(at: NSPoint(x: rect.midX - hs.width / 2, y: rect.midY - ps.height - hs.height - 7))
            }
            return
        }

        // Has files — divider + small plus icon
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: 14, y: rect.maxY))
        sep.line(to: NSPoint(x: viewWidth - 14, y: rect.maxY))
        NSColor(white: 1, alpha: 0.07).setStroke()
        sep.lineWidth = 0.5; sep.stroke()

        let plusSymbol = isDragOver ? "plus.circle.fill" : "plus.circle"
        let plusColor  = isDragOver ? NSColor.systemBlue : NSColor(white: 1, alpha: 0.22)
        let plusCfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .thin)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: plusColor))
        if let img = NSImage(systemSymbolName: plusSymbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(plusCfg) {
            let s = NSSize(width: 17, height: 17)
            img.draw(in: NSRect(x: rect.midX - s.width / 2,
                                y: rect.midY - s.height / 2,
                                width: s.width, height: s.height))
        }
    }

    private func drawActionBar() {
        guard !storedFiles.isEmpty else { return }

        // Top separator
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: 10, y: actionBarRect.maxY))
        sep.line(to: NSPoint(x: viewWidth - 10, y: actionBarRect.maxY))
        NSColor(white: 1, alpha: 0.07).setStroke()
        sep.lineWidth = 0.5; sep.stroke()

        // Center divider
        let mid = NSBezierPath()
        mid.move(to: NSPoint(x: viewWidth / 2, y: actionBarRect.minY + 6))
        mid.line(to: NSPoint(x: viewWidth / 2, y: actionBarRect.maxY - 6))
        NSColor(white: 1, alpha: 0.07).setStroke()
        mid.lineWidth = 0.5; mid.stroke()

        let hasSelection = !selectedIndices.isEmpty
        let compressSymbol = isCompressing ? "hourglass" : "archivebox.fill"
        let compressLabel  = isCompressing ? "Zipping…" : "Zip"
        drawActionButton(symbol: compressSymbol, label: compressLabel,
                         center: NSPoint(x: viewWidth / 4, y: actionBarRect.midY),
                         isHovered: hoveredActionButton == .compress && !isCompressing,
                         isActive: hasSelection && !isCompressing)
        drawActionButton(symbol: "dot.radiowaves.left.and.right", label: "AirDrop",
                         center: NSPoint(x: 3 * viewWidth / 4, y: actionBarRect.midY),
                         isHovered: hoveredActionButton == .airDrop,
                         isActive: hasSelection)
    }

    private func drawActionButton(symbol: String, label: String,
                                  center: NSPoint, isHovered: Bool, isActive: Bool) {
        let color: NSColor = isHovered ? .systemBlue
            : NSColor(white: 1, alpha: isActive ? 0.65 : 0.22)

        if isHovered {
            let hRect = NSRect(x: center.x - 26, y: actionBarRect.minY + 3,
                               width: 52, height: actionBarHeight - 6)
            let bg = NSBezierPath(roundedRect: hRect, xRadius: 6, yRadius: 6)
            NSColor.systemBlue.withAlphaComponent(0.18).setFill(); bg.fill()
        }

        // Icon
        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: color))
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) {
            let s = NSSize(width: 14, height: 14)
            img.draw(in: NSRect(x: center.x - s.width / 2, y: center.y + 1,
                                width: s.width, height: s.height))
        }

        // Label below icon
        let labelAttr = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: color
        ])
        let ls = labelAttr.size()
        labelAttr.draw(at: NSPoint(x: center.x - ls.width / 2, y: center.y - ls.height - 1))
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didDrag = false
        windowDragScreenOrigin = NSEvent.mouseLocation
        windowFrameOriginAtDragStart = window?.frame.origin ?? .zero

        // X button
        if let hovered = hoveredIndex, closeButtonRect(for: hovered).contains(mouseDownPoint) {
            removeFileAt(hovered)
            mouseDownFileIndex = nil
            return
        }
        // Action bar buttons absorb the down event (handled on mouseUp)
        if !storedFiles.isEmpty,
           compressButtonRect.insetBy(dx: -5, dy: -4).contains(mouseDownPoint) ||
           airDropButtonRect.insetBy(dx: -5, dy: -4).contains(mouseDownPoint) {
            mouseDownFileIndex = nil
            return
        }
        mouseDownFileIndex = fileIndex(at: mouseDownPoint)
    }

    override func mouseDragged(with event: NSEvent) {
        if let idx = mouseDownFileIndex {
            guard !didDrag else { return }
            let pt = convert(event.locationInWindow, from: nil)
            guard hypot(pt.x - mouseDownPoint.x, pt.y - mouseDownPoint.y) > 4 else { return }
            didDrag = true
            beginFileDrag(at: idx, event: event)
        } else {
            let cur = NSEvent.mouseLocation
            window?.setFrameOrigin(NSPoint(
                x: windowFrameOriginAtDragStart.x + cur.x - windowDragScreenOrigin.x,
                y: windowFrameOriginAtDragStart.y + cur.y - windowDragScreenOrigin.y
            ))
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownFileIndex = nil; isDraggingOut = false; didDrag = false }
        guard !didDrag else { return }
        let pt = convert(event.locationInWindow, from: nil)

        // Action bar button taps
        if !storedFiles.isEmpty {
            if compressButtonRect.insetBy(dx: -5, dy: -4).contains(pt) { compressFiles(); return }
            if airDropButtonRect.insetBy(dx: -5, dy: -4).contains(pt)  { airDropFiles();  return }
        }

        guard let idx = mouseDownFileIndex, fileIndex(at: pt) == idx else { return }
        if event.modifierFlags.contains(.command) {
            if selectedIndices.contains(idx) { selectedIndices.remove(idx) } else { selectedIndices.insert(idx) }
        } else {
            selectedIndices = [idx]
        }
        copySelectedToClipboard()
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        let newHover = fileIndex(at: pt)
        if newHover != hoveredIndex { hoveredIndex = newHover; needsDisplay = true }

        var newAction: ActionButton? = nil
        if !storedFiles.isEmpty {
            if compressButtonRect.insetBy(dx: -5, dy: -4).contains(pt) { newAction = .compress }
            else if airDropButtonRect.insetBy(dx: -5, dy: -4).contains(pt) { newAction = .airDrop }
        }
        if newAction != hoveredActionButton { hoveredActionButton = newAction; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil; hoveredActionButton = nil; needsDisplay = true
    }

    // MARK: - Clipboard

    private func copySelectedToClipboard() {
        let indices = selectedIndices.sorted().filter { $0 < storedFiles.count }
        guard !indices.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(indices.map { storedFiles[$0] as NSURL })
        flashIndices = Set(indices); needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.flashIndices = []; self?.needsDisplay = true
        }
    }

    // MARK: - Compress

    @objc private func compressFiles() {
        guard !isCompressing else { return }
        let indices = selectedIndices.isEmpty
            ? Array(0..<storedFiles.count)
            : selectedIndices.sorted().filter { $0 < storedFiles.count }
        guard !indices.isEmpty else { return }
        let files = indices.map { storedFiles[$0] }

        // Ask user for archive name (default: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let defaultName = "Archive \(formatter.string(from: Date()))"

        let alert = NSAlert()
        alert.messageText = "Name the Archive"
        alert.informativeText = "Choose a name for the ZIP file."
        alert.addButton(withTitle: "Compress")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        field.stringValue = defaultName
        field.selectText(nil)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = name.isEmpty ? defaultName : name

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        var zipURL = tmp.appendingPathComponent("\(base).zip")
        var n = 1
        while FileManager.default.fileExists(atPath: zipURL.path) {
            zipURL = tmp.appendingPathComponent("\(base) \(n).zip"); n += 1
        }

        isCompressing = true; needsDisplay = true

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        // -0 = store mode (no compression) — maximum speed for clipboard transfers
        proc.arguments = ["-0", "-j", zipURL.path] + files.map { $0.path }

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isCompressing = false
                guard p.terminationStatus == 0 else { self.needsDisplay = true; return }
                for idx in indices.sorted().reversed() where idx < self.storedFiles.count {
                    self.storedFiles.remove(at: idx)
                }
                self.storedFiles.append(zipURL)
                let newIdx = self.storedFiles.count - 1
                self.selectedIndices = [newIdx]
                self.flashIndices    = [newIdx]
                self.saveFiles()
                self.updateWindowSize()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    self.flashIndices = []; self.needsDisplay = true
                }
            }
        }
        try? proc.run()
    }

    // MARK: - AirDrop

    @objc private func airDropFiles() {
        let indices = selectedIndices.isEmpty
            ? Array(0..<storedFiles.count)
            : selectedIndices.sorted().filter { $0 < storedFiles.count }
        let files = indices.map { storedFiles[$0] }
        guard !files.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: files)
    }

    // MARK: - Right-click menu

    override func rightMouseUp(with event: NSEvent) {
        let pt  = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()

        if selectedIndices.count > 1 {
            let copy = NSMenuItem(title: "Copy \(selectedIndices.count) Selected Files",
                                  action: #selector(copySelected), keyEquivalent: "")
            copy.target = self; menu.addItem(copy)

            let rem = NSMenuItem(title: "Remove \(selectedIndices.count) Selected Files",
                                 action: #selector(removeSelected), keyEquivalent: "")
            rem.target = self; menu.addItem(rem)
            menu.addItem(.separator())
        }

        if let idx = fileIndex(at: pt) {
            let name = storedFiles[idx].lastPathComponent
            let item = NSMenuItem(title: "Remove \"\(name)\"",
                                  action: #selector(removeFile(_:)), keyEquivalent: "")
            item.tag = idx; item.target = self; menu.addItem(item)
        }

        if !storedFiles.isEmpty {
            if !menu.items.isEmpty { menu.addItem(.separator()) }

            let selDesc = selectedIndices.isEmpty ? "All Files"
                : (selectedIndices.count == 1 ? "Selected File" : "\(selectedIndices.count) Selected Files")

            let compress = NSMenuItem(title: "Compress \(selDesc)",
                                      action: #selector(compressFiles), keyEquivalent: "")
            compress.target = self; menu.addItem(compress)

            let airdrop = NSMenuItem(title: "AirDrop \(selDesc)",
                                     action: #selector(airDropFiles), keyEquivalent: "")
            airdrop.target = self; menu.addItem(airdrop)

            menu.addItem(.separator())

            if selectedIndices.count < storedFiles.count {
                let selAll = NSMenuItem(title: "Select All", action: #selector(selectAllFiles),
                                        keyEquivalent: "a")
                selAll.keyEquivalentModifierMask = [.command]; selAll.target = self
                menu.addItem(selAll)
            }

            let clear = NSMenuItem(title: "Clear All", action: #selector(clearAll), keyEquivalent: "\u{08}")
            clear.keyEquivalentModifierMask = [.command]; clear.target = self
            menu.addItem(clear)
        }

        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide Shelf", action: #selector(hideShelf), keyEquivalent: "")
        hide.target = self; menu.addItem(hide)
        let quit = NSMenuItem(title: "Quit FileShelf", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self; menu.addItem(quit)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func copySelected()    { copySelectedToClipboard() }
    @objc private func hideShelf()       { (window as? ShelfWindow)?.hideAnimated() }
    @objc private func quitApp()         { NSApp.terminate(nil) }
    @objc func selectAllFiles()          { guard !storedFiles.isEmpty else { return }
                                           selectedIndices = Set(0..<storedFiles.count); needsDisplay = true }

    @objc private func removeSelected() {
        for idx in selectedIndices.sorted().reversed() where idx < storedFiles.count {
            storedFiles.remove(at: idx)
        }
        selectedIndices = []; flashIndices = []; hoveredIndex = nil
        saveFiles(); updateWindowSize()
    }

    @objc private func removeFile(_ sender: NSMenuItem) { removeFileAt(sender.tag) }

    @objc func clearAll() {
        storedFiles.removeAll(); selectedIndices = []; flashIndices = []; hoveredIndex = nil
        saveFiles(); updateWindowSize()
    }

    private func removeFileAt(_ idx: Int) {
        guard idx < storedFiles.count else { return }
        storedFiles.remove(at: idx)
        hoveredIndex = nil
        selectedIndices = Set(selectedIndices.compactMap { i in i == idx ? nil : (i > idx ? i - 1 : i) })
        flashIndices    = Set(flashIndices.compactMap    { i in i == idx ? nil : (i > idx ? i - 1 : i) })
        saveFiles(); updateWindowSize()
    }

    func addFiles(_ urls: [URL]) {
        for url in urls where !storedFiles.contains(url) { storedFiles.append(url) }
        saveFiles(); updateWindowSize(); animateBounce()
    }

    // MARK: - Drag in

    private static let fileRelatedTypes: Set<NSPasteboard.PasteboardType> = [
        .fileURL,
        NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        NSPasteboard.PasteboardType("public.url"),
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
    ]

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        // Modern file-URL type (files + folders)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty { return urls }
        // Fallback: read all URL objects and keep only local ones (catches some Electron folder drags)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let local = urls.filter { $0.isFileURL }
            if !local.isEmpty { return local }
        }
        // Legacy NSFilenamesPboardType (Electron/Chromium)
        if let paths = pasteboard.propertyList(
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            return paths.compactMap {
                FileManager.default.fileExists(atPath: $0) ? URL(fileURLWithPath: $0) : nil
            }
        }
        // public.url as string (some apps write a file:// URL as plain text)
        if let str = pasteboard.string(forType: NSPasteboard.PasteboardType("public.url")),
           let url = URL(string: str), url.isFileURL { return [url] }
        return []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Check TYPES only — don't try to read data here;
        // Electron/Chromium makes data unavailable until performDragOperation.
        guard !isDraggingOut else { return [] }
        let pbTypes = Set(sender.draggingPasteboard.types ?? [])
        guard !pbTypes.isDisjoint(with: ShelfView.fileRelatedTypes) else { return [] }
        isDragOver = true; needsDisplay = true; return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isDraggingOut else { return [] }
        // Accept whatever the source offers so we don't reject Electron's .move-only drags
        let mask = sender.draggingSourceOperationMask
        return mask.contains(.copy) ? .copy : (mask.isEmpty ? .copy : .copy)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { isDragOver = false; needsDisplay = true }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragOver = false
        let urls = fileURLs(from: sender.draggingPasteboard)
        var added = false
        for url in urls where !storedFiles.contains(url) { storedFiles.append(url); added = true }
        guard added else { return false }
        saveFiles(); updateWindowSize(); animateBounce(); return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) { isDragOver = false; needsDisplay = true }

    // MARK: - Drag out

    private func beginFileDrag(at index: Int, event: NSEvent) {
        guard index < storedFiles.count else { return }
        isDraggingOut = true
        let indices = (selectedIndices.contains(index) && selectedIndices.count > 1)
            ? selectedIndices.sorted() : [index]
        var items: [NSDraggingItem] = []
        for i in indices {
            guard i < storedFiles.count else { continue }
            let url  = storedFiles[i]
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let rect = slotRect(for: i)
            item.setDraggingFrame(NSRect(x: rect.midX - 16, y: rect.midY - 8, width: 32, height: 32), contents: icon)
            items.append(item)
        }
        guard !items.isEmpty else { return }
        beginDraggingSession(with: items, event: event, source: self)
            .animatesToStartingPositionsOnCancelOrFail = true
    }

    // MARK: - Animation

    private func animateBounce() {
        guard let layer else { return }
        let anim = CAKeyframeAnimation(keyPath: "transform.scale")
        anim.values = [1.0, 1.07, 0.97, 1.01, 1.0]; anim.duration = 0.3
        layer.add(anim, forKey: "bounce")
    }
}

// MARK: - NSDraggingSource
extension ShelfView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDraggingOut = false; needsDisplay = true
    }
}

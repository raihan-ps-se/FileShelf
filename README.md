# FileShelf

A lightweight macOS utility that gives you a floating file shelf — a temporary clipboard for files. Drop files in from anywhere, drag them out wherever you need them.

![FileShelf](https://placeholder/screenshot.png)

---

## What it does

FileShelf lives in your menu bar as a small floating panel. Instead of juggling Finder windows or losing track of files mid-task, you drop them onto the shelf and retrieve them when you need them.

- **Drop in** from Finder, Cursor, VS Code, or any app
- **Drag out** to any drop target (email, Finder, Slack, etc.)
- **Click** a file to copy it to the clipboard for Cmd+V anywhere
- Files **persist** across relaunches until you clear them

---

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools (`xcode-select --install`)

---

## Install

### Pre-built (easiest)

1. Download `FileShelf.app.zip` from [Releases](https://github.com/raihan-ps-se/FileShelf/releases)
2. Unzip and drag `FileShelf.app` to `/Applications`
3. Right-click → **Open** → **Open** (bypasses Gatekeeper for unsigned apps)

### Build from source

```bash
git clone https://github.com/raihan-ps-se/FileShelf.git
cd FileShelf
bash build.sh
```

The script builds the binary, generates the app icon, and packages everything into `FileShelf.app`. Copy it to `/Applications` for permanent install.

---

## Features

| Feature | How |
|---|---|
| Show / hide shelf | **⌥Space** (global, no permissions needed) |
| Add file from clipboard | Hold **⌘C** for 3 seconds |
| Auto-show on drag | Hold a drag for **1.5 seconds** |
| Select file + copy to clipboard | Click a file |
| Multi-select | **⌘+Click** or right-click → Select All |
| Select all | **⌘A** |
| Remove a file | Hover → click the **×** button |
| Remove selected | **⌘Delete** |
| Clear all files | **⌘Delete** with nothing selected |
| Compress to ZIP | Action bar → **Zip** (prompts for name, saves to /tmp) |
| AirDrop | Action bar → **AirDrop** |
| Drag files out | Drag from shelf to any drop target |
| Right-click menu | Remove, compress, AirDrop, select all, hide, quit |
| Move shelf | Drag empty area of the shelf |
| Quit | **⌘Q** (when shelf is focused) |
| Launch at login | Right-click menu bar icon → Launch at Login |

---

## Permissions

- **Accessibility** — optional. Enables the Cmd+C hold-to-show trigger. FileShelf will prompt on first launch; you can deny it and everything else still works.
- No network access, no file modification, no background processes beyond the app itself.

---

## How to use

**Basic workflow:**
1. In Finder (or Cursor, etc.), start dragging a file
2. Hold the drag for 1.5 seconds — FileShelf appears automatically
3. Drop the file onto the shelf
4. Go to your destination app, then drag the file out of the shelf (or click it to Cmd+V)

**Keyboard workflow:**
1. Select a file and press **⌘C** — hold it for 3 seconds
2. FileShelf appears and the file is already added
3. Cmd+V to paste wherever you need it

**Toggle anytime:** Press **⌥Space** from any app.

---

## Uninstall

```bash
# Remove the app
rm -rf /Applications/FileShelf.app

# Remove saved preferences
defaults delete com.fileshelf.app
```

---

## Project structure

```
FileShelf/
├── Sources/FileShelf/
│   ├── main.swift          # Entry point
│   ├── AppDelegate.swift   # App lifecycle, menu bar, global triggers
│   ├── ShelfWindow.swift   # Floating NSPanel
│   └── ShelfView.swift     # All UI drawing and interaction
├── Package.swift           # Swift Package Manager config
├── build.sh                # Build + bundle script
├── make_icon.swift         # App icon generator
└── README.md
```

---

## License

MIT — see [LICENSE](LICENSE) for details.

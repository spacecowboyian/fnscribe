import AppKit
import Foundation

struct TranscriptEntry: Codable {
    let id: String
    let createdAt: String
    let durationSeconds: Double
    let audioPath: String
    let rawText: String
    let cleanedText: String
}

struct AppStatus: Codable {
    let state: String
    let message: String
    let updatedAt: String
}

final class MenuApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let projectRoot = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["FNSCRIBE_PROJECT_ROOT"] ?? FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    private var historyURL: URL { projectRoot.appendingPathComponent("public/history.json") }
    private var statusURL: URL { projectRoot.appendingPathComponent("public/status.json") }
    private var historyPageURL: URL {
        let port = ProcessInfo.processInfo.environment["FNSCRIBE_UI_PORT"] ?? "8765"
        return URL(string: "http://127.0.0.1:\(port)/fn-scribe-history.html")!
    }
    private let statusDateFormatter = ISO8601DateFormatter()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let button = statusItem.button {
            button.toolTip = "FnScribe recent transcripts"
            button.imagePosition = .imageOnly
        }
        rebuildMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.rebuildMenu()
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = effectiveStatus(loadStatus())
        let entries = loadEntries(limit: 5)
        updateStatusButton(status)

        let statusItem = NSMenuItem(title: statusTitle(status), action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(NSMenuItem.separator())

        if entries.isEmpty {
            let empty = NSMenuItem(title: "No transcripts yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (index, entry) in entries.enumerated() {
                let parent = NSMenuItem(title: "\(index + 1). \(summary(entry.cleanedText))", action: nil, keyEquivalent: "")
                let submenu = NSMenu()

                let preview = NSMenuItem(title: entry.cleanedText, action: nil, keyEquivalent: "")
                preview.isEnabled = false
                submenu.addItem(preview)

                let copy = NSMenuItem(title: "Copy Transcript", action: #selector(copyTranscript(_:)), keyEquivalent: "")
                copy.target = self
                copy.representedObject = entry.cleanedText
                submenu.addItem(copy)

                let copyRaw = NSMenuItem(title: "Copy Raw Transcript", action: #selector(copyTranscript(_:)), keyEquivalent: "")
                copyRaw.target = self
                copyRaw.representedObject = entry.rawText
                submenu.addItem(copyRaw)

                let meta = NSMenuItem(title: "\(entry.createdAt) • \(String(format: "%.1fs", entry.durationSeconds))", action: nil, keyEquivalent: "")
                meta.isEnabled = false
                submenu.addItem(meta)

                parent.submenu = submenu
                menu.addItem(parent)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let openHistory = NSMenuItem(title: "Open History Page", action: #selector(openHistoryPage), keyEquivalent: "")
        openHistory.target = self
        menu.addItem(openHistory)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit FnScribe Menu", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        self.statusItem.menu = menu
    }

    private func updateStatusButton(_ status: AppStatus?) {
        guard let button = statusItem.button else { return }
        let state = status?.state ?? "idle"
        button.title = ""
        button.image = badgeImage(for: state)
        button.image?.isTemplate = false
    }

    private func badgeImage(for state: String) -> NSImage {
        let size = NSSize(width: 31, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        let background: NSColor?
        let foreground: NSColor

        switch state {
        case "recording":
            background = NSColor.systemGreen
            foreground = .black
        case "transcribing":
            background = NSColor.systemYellow
            foreground = .black
        default:
            background = nil
            foreground = .white
        }

        if let background {
            background.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
        }

        let text = "Fn" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: foreground
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2
            ),
            withAttributes: attributes
        )

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func loadEntries(limit: Int) -> [TranscriptEntry] {
        guard let data = try? Data(contentsOf: historyURL),
              let entries = try? JSONDecoder().decode([TranscriptEntry].self, from: data) else {
            return []
        }
        return Array(entries.prefix(limit))
    }

    private func loadStatus() -> AppStatus? {
        guard let data = try? Data(contentsOf: statusURL) else { return nil }
        return try? JSONDecoder().decode(AppStatus.self, from: data)
    }

    private func effectiveStatus(_ status: AppStatus?) -> AppStatus? {
        guard let status else { return nil }
        guard status.state == "recording" || status.state == "transcribing" else { return status }
        guard let updatedAt = statusDateFormatter.date(from: status.updatedAt) else { return status }
        if Date().timeIntervalSince(updatedAt) > 600 {
            return AppStatus(state: "idle", message: "Ready", updatedAt: status.updatedAt)
        }
        return status
    }

    private func statusTitle(_ status: AppStatus?) -> String {
        guard let status else { return "FnScribe: status unavailable" }
        return "FnScribe: \(status.state) - \(status.message)"
    }

    private func summary(_ text: String) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        if oneLine.count <= 58 { return oneLine }
        return String(oneLine.prefix(55)) + "..."
    }

    @objc private func copyTranscript(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func refreshNow() {
        rebuildMenu()
    }

    @objc private func openHistoryPage() {
        NSWorkspace.shared.open(historyPageURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = MenuApp()
app.delegate = delegate
app.run()

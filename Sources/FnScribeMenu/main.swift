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
            // One click on a transcript copies it. The full text lives in the
            // tooltip and on the history page, so the menu stays short.
            for (index, entry) in entries.enumerated() {
                let item = NSMenuItem(
                    title: summary(entry.cleanedText),
                    action: #selector(copyTranscript(_:)),
                    keyEquivalent: index < 9 ? "\(index + 1)" : ""
                )
                item.target = self
                item.representedObject = entry.cleanedText
                item.toolTip = entry.cleanedText
                menu.addItem(item)
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
    }

    private func badgeImage(for state: String) -> NSImage {
        let size = NSSize(width: 31, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        let background: NSColor?
        let foreground: NSColor

        // Idle draws as a template image so macOS tints it for the current menu
        // bar, which follows the wallpaper rather than the light/dark setting.
        // A hardcoded color disappears against half the backgrounds.
        let isIdle = state != "recording" && state != "transcribing"
        switch state {
        case "recording":
            background = NSColor.systemGreen
            foreground = .black
        case "transcribing":
            background = NSColor.systemYellow
            foreground = .black
        default:
            background = nil
            foreground = .black
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
        image.isTemplate = isIdle
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
        let trimmed = oneLine.trimmingCharacters(in: .whitespaces)
        if trimmed.count <= 45 { return trimmed }
        return String(trimmed.prefix(44)) + "\u{2026}"
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

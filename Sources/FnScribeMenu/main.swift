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
    private var historyPageURL: URL { projectRoot.appendingPathComponent("public/fn-scribe-history.html") }
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.title = "Fn"
        statusItem.button?.toolTip = "FnScribe recent transcripts"
        rebuildMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.rebuildMenu()
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = loadStatus()
        let entries = loadEntries(limit: 5)

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

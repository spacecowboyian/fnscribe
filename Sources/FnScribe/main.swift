import AppKit
import AVFoundation
import CoreGraphics
import Foundation

let appName = "FnScribe"
let holdDelay: TimeInterval = 0.18
let doubleTapWindow: TimeInterval = 0.42
let placeholderText = ProcessInfo.processInfo.environment["FNSCRIBE_PLACEHOLDER"] ?? "transcribing..."
let historyLimit = Int(ProcessInfo.processInfo.environment["FNSCRIBE_HISTORY_LIMIT"] ?? "50") ?? 50
let soundEnabled = (ProcessInfo.processInfo.environment["FNSCRIBE_SOUND"] ?? "1") != "0"
let startSoundName = ProcessInfo.processInfo.environment["FNSCRIBE_START_SOUND"] ?? "Ping"
let stopSoundName = ProcessInfo.processInfo.environment["FNSCRIBE_STOP_SOUND"] ?? "Pop"
let completeSoundName = ProcessInfo.processInfo.environment["FNSCRIBE_COMPLETE_SOUND"] ?? "Glass"
let cleanupMode = ProcessInfo.processInfo.environment["FNSCRIBE_CLEANUP_MODE"] ?? "auto"
let triggerKey = TriggerKey.fromEnvironment()
let projectRoot = URL(
    fileURLWithPath: ProcessInfo.processInfo.environment["FNSCRIBE_PROJECT_ROOT"] ?? FileManager.default.currentDirectoryPath,
    isDirectory: true
)
let logFile = projectRoot.appendingPathComponent("work/fn-scribe.log")
var activeSounds: [NSSound] = []

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

    static var idle: AppStatus {
        AppStatus(
            state: "idle",
            message: "Ready",
            updatedAt: ISO8601DateFormatter.display.string(from: Date())
        )
    }
}

final class Store {
    let baseDir: URL
    let audioDir: URL
    let historyFile: URL
    let statusFile: URL
    let outputDir: URL
    let publicHistoryFile: URL
    let publicStatusFile: URL
    let htmlFile: URL

    init() throws {
        if let override = ProcessInfo.processInfo.environment["FNSCRIBE_HOME"], !override.isEmpty {
            baseDir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            baseDir = projectRoot.appendingPathComponent("work/fn-scribe-store", isDirectory: true)
        }
        audioDir = baseDir.appendingPathComponent("audio", isDirectory: true)
        historyFile = baseDir.appendingPathComponent("history.json")
        statusFile = baseDir.appendingPathComponent("status.json")
        outputDir = projectRoot.appendingPathComponent("public", isDirectory: true)
        publicHistoryFile = outputDir.appendingPathComponent("history.json")
        publicStatusFile = outputDir.appendingPathComponent("status.json")
        htmlFile = outputDir.appendingPathComponent("fn-scribe-history.html")

        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: historyFile.path) {
            try "[]".write(to: historyFile, atomically: true, encoding: .utf8)
        }
        if !FileManager.default.fileExists(atPath: statusFile.path) {
            try JSONEncoder.pretty.encode(AppStatus.idle).write(to: statusFile, options: .atomic)
        }
        try enforceHistoryLimit()
        try mirrorPublicFiles(entries: load(), status: loadStatus())
    }

    func load() -> [TranscriptEntry] {
        guard let data = try? Data(contentsOf: historyFile),
              let entries = try? JSONDecoder().decode([TranscriptEntry].self, from: data) else {
            return []
        }
        return entries
    }

    func append(_ entry: TranscriptEntry) throws {
        var entries = load()
        entries.insert(entry, at: 0)
        entries = trim(entries)
        try writeHistory(entries)
        try renderHTML(entries, status: loadStatus())
    }

    func loadStatus() -> AppStatus {
        guard let data = try? Data(contentsOf: statusFile),
              let status = try? JSONDecoder().decode(AppStatus.self, from: data) else {
            return .idle
        }
        return status
    }

    func setStatus(_ state: String, _ message: String) {
        let status = AppStatus(
            state: state,
            message: message,
            updatedAt: ISO8601DateFormatter.display.string(from: Date())
        )
        do {
            try JSONEncoder.pretty.encode(status).write(to: statusFile, options: .atomic)
            try JSONEncoder.pretty.encode(status).write(to: publicStatusFile, options: .atomic)
            try renderHTML(load(), status: status)
        } catch {
            log("Could not update UI status: \(error.localizedDescription)")
        }
    }

    func writeHistory(_ entries: [TranscriptEntry]) throws {
        let data = try JSONEncoder.pretty.encode(entries)
        try data.write(to: historyFile, options: .atomic)
        try data.write(to: publicHistoryFile, options: .atomic)
    }

    func mirrorPublicFiles(entries: [TranscriptEntry], status: AppStatus) throws {
        try JSONEncoder.pretty.encode(entries).write(to: publicHistoryFile, options: .atomic)
        try JSONEncoder.pretty.encode(status).write(to: publicStatusFile, options: .atomic)
    }

    func enforceHistoryLimit() throws {
        let entries = load()
        let trimmed = trim(entries)
        if trimmed.count != entries.count {
            try writeHistory(trimmed)
        }
    }

    func trim(_ entries: [TranscriptEntry]) -> [TranscriptEntry] {
        guard historyLimit > 0, entries.count > historyLimit else { return entries }
        let keep = Array(entries.prefix(historyLimit))
        let remove = entries.dropFirst(historyLimit)
        for entry in remove {
            try? FileManager.default.removeItem(atPath: entry.audioPath)
        }
        return keep
    }

    func renderHTML(_ entries: [TranscriptEntry], status: AppStatus) throws {
        let rows = entries.map { entry in
            """
            <article class="entry">
              <header>
                <time>\(escape(entry.createdAt))</time>
                <span>\(String(format: "%.1fs", entry.durationSeconds))</span>
              </header>
              <textarea readonly>\(escape(entry.cleanedText))</textarea>
              <div class="actions">
                <button onclick="copyText(this)">Copy</button>
                <details>
                  <summary>Raw</summary>
                  <pre>\(escape(entry.rawText))</pre>
                </details>
              </div>
            </article>
            """
        }.joined(separator: "\n")

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>FnScribe History</title>
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
            body { margin: 0; background: Canvas; color: CanvasText; }
            main { max-width: 900px; margin: 0 auto; padding: 24px 16px 56px; }
            h1 { font-size: 28px; margin: 0 0 6px; }
            .sub { margin: 0 0 14px; color: color-mix(in srgb, CanvasText 68%, transparent); }
            .live { display: inline-flex; align-items: center; gap: 7px; margin: 0 0 14px; font-size: 13px; color: color-mix(in srgb, CanvasText 68%, transparent); }
            .live::before { content: ""; width: 8px; height: 8px; border-radius: 999px; background: #9a9a9a; }
            .live.connected::before { background: #24a148; }
            .live.static::before { background: #d14b31; }
            .status { display: flex; align-items: center; justify-content: space-between; gap: 14px; border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); border-radius: 8px; padding: 12px 14px; margin: 0 0 20px; background: color-mix(in srgb, Canvas 88%, CanvasText 12%); }
            .status strong { text-transform: uppercase; font-size: 12px; letter-spacing: .04em; }
            .status p { margin: 3px 0 0; }
            .status time { font-size: 12px; color: color-mix(in srgb, CanvasText 62%, transparent); white-space: nowrap; }
            .status.recording { border-color: #d14b31; background: color-mix(in srgb, Canvas 84%, #d14b31 16%); }
            .status.transcribing { border-color: #2f6fbd; background: color-mix(in srgb, Canvas 84%, #2f6fbd 16%); }
            .status.failed { border-color: #a23131; background: color-mix(in srgb, Canvas 84%, #a23131 16%); }
            .status .pulse { width: 10px; height: 10px; border-radius: 999px; background: currentColor; opacity: .45; }
            .status.recording .pulse, .status.transcribing .pulse { animation: pulse 850ms ease-in-out infinite alternate; opacity: 1; }
            @keyframes pulse { from { transform: scale(.72); } to { transform: scale(1.18); } }
            .entry { border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); border-radius: 8px; padding: 14px; margin: 14px 0; background: color-mix(in srgb, Canvas 92%, CanvasText 8%); }
            header { display: flex; justify-content: space-between; gap: 16px; font-size: 13px; color: color-mix(in srgb, CanvasText 70%, transparent); margin-bottom: 10px; }
            textarea { width: 100%; min-height: 120px; box-sizing: border-box; resize: vertical; border: 1px solid color-mix(in srgb, CanvasText 20%, transparent); border-radius: 6px; padding: 10px; font: 15px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace; background: Canvas; color: CanvasText; }
            .actions { display: flex; align-items: center; gap: 14px; margin-top: 10px; }
            button { border: 1px solid color-mix(in srgb, CanvasText 22%, transparent); border-radius: 6px; padding: 7px 11px; background: ButtonFace; color: ButtonText; cursor: pointer; }
            details { font-size: 13px; }
            pre { white-space: pre-wrap; max-height: 260px; overflow: auto; }
          </style>
        </head>
        <body>
          <main>
            <h1>FnScribe History</h1>
            <p class="sub">Newest transcripts first. This page refreshes automatically.</p>
            <p id="live-indicator" class="live">Checking live updates...</p>
            <section id="status" class="status \(escape(status.state))">
              <span class="pulse" aria-hidden="true"></span>
              <div>
                <strong id="status-state">\(escape(status.state))</strong>
                <p id="status-message">\(escape(status.message))</p>
              </div>
              <time id="status-updated">\(escape(status.updatedAt))</time>
            </section>
            <section id="entries">\(rows.isEmpty ? "<p>No transcripts yet.</p>" : rows)</section>
          </main>
          <script>
            const entriesEl = document.getElementById('entries');
            const statusEl = document.getElementById('status');
            const stateEl = document.getElementById('status-state');
            const messageEl = document.getElementById('status-message');
            const updatedEl = document.getElementById('status-updated');
            const liveEl = document.getElementById('live-indicator');

            function esc(text) {
              return String(text ?? '').replace(/[&<>"']/g, ch => ({
                '&': '&amp;',
                '<': '&lt;',
                '>': '&gt;',
                '"': '&quot;',
                "'": '&#039;'
              }[ch]));
            }

            function renderStatus(status) {
              const state = status?.state || 'idle';
              statusEl.className = `status ${state}`;
              stateEl.textContent = state;
              messageEl.textContent = status?.message || 'Ready';
              updatedEl.textContent = status?.updatedAt || '';
            }

            function renderEntries(entries) {
              if (!Array.isArray(entries) || entries.length === 0) {
                entriesEl.innerHTML = '<p>No transcripts yet.</p>';
                return;
              }
              entriesEl.innerHTML = entries.map(entry => `
                <article class="entry">
                  <header>
                    <time>${esc(entry.createdAt)}</time>
                    <span>${Number(entry.durationSeconds || 0).toFixed(1)}s</span>
                  </header>
                  <textarea readonly>${esc(entry.cleanedText)}</textarea>
                  <div class="actions">
                    <button onclick="copyText(this)">Copy</button>
                    <details>
                      <summary>Raw</summary>
                      <pre>${esc(entry.rawText)}</pre>
                    </details>
                  </div>
                </article>
              `).join('');
            }

            async function refreshLiveData() {
              if (location.protocol === 'file:') {
                liveEl.className = 'live static';
                liveEl.textContent = 'Static file opened. Use http://127.0.0.1:8765/fn-scribe-history.html for live updates.';
                return;
              }
              try {
                const stamp = Date.now();
                const [statusResponse, historyResponse] = await Promise.all([
                  fetch(`status.json?${stamp}`, { cache: 'no-store' }),
                  fetch(`history.json?${stamp}`, { cache: 'no-store' })
                ]);
                if (!statusResponse.ok || !historyResponse.ok) return;
                renderStatus(await statusResponse.json());
                renderEntries(await historyResponse.json());
                liveEl.className = 'live connected';
                liveEl.textContent = 'Live updates connected.';
              } catch {
                liveEl.className = 'live static';
                liveEl.textContent = 'Live updates unavailable. Open this page through the FnScribe local server.';
              }
            }

            async function copyText(button) {
              const text = button.closest('.entry').querySelector('textarea').value;
              await navigator.clipboard.writeText(text);
              const old = button.textContent;
              button.textContent = 'Copied';
              setTimeout(() => button.textContent = old, 900);
            }

            setInterval(refreshLiveData, 500);
            refreshLiveData();
          </script>
        </body>
        </html>
        """
        try html.write(to: htmlFile, atomically: true, encoding: .utf8)
    }
}

final class Recorder: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var startedAt = Date()
    private let store: Store
    private let transcriber: Transcriber
    private let pasteController: PasteController

    init(store: Store, transcriber: Transcriber) {
        self.store = store
        self.transcriber = transcriber
        self.pasteController = PasteController()
    }

    var isRecording: Bool { recorder?.isRecording == true }

    func start(mode: String) {
        guard !isRecording else { return }
        let id = ISO8601DateFormatter.fileSafe.string(from: Date())
        let url = store.audioDir.appendingPathComponent("\(id)-\(mode).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder?.delegate = self
            recorder?.prepareToRecord()
            recorder?.record()
            startedAt = Date()
            store.setStatus("recording", "Recording \(mode). Release \(triggerKey.label) to stop.")
            playCue(startSoundName)
            log("Recording \(mode)...")
        } catch {
            store.setStatus("failed", "Could not start recording.")
            log("Could not start recording: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard let recorder, recorder.isRecording else { return }
        recorder.stop()
        let url = recorder.url
        let duration = Date().timeIntervalSince(startedAt)
        self.recorder = nil
        playCue(stopSoundName)
        store.setStatus("transcribing", "Transcribing \(String(format: "%.1f", duration)) seconds of audio.")
        log("Recording stopped. Transcribing...")
        let pasteToken = pasteController.pastePlaceholder()
        Task {
            await finish(url: url, duration: duration, pasteToken: pasteToken)
        }
    }

    private func finish(url: URL, duration: Double, pasteToken: PasteToken?) async {
        do {
            let raw = try await transcriber.transcribe(url)
            store.setStatus("transcribing", "Assessing transcript cleanup.")
            let cleaned = try await transcriber.cleanIfNeeded(raw)
            pasteController.replacePlaceholder(with: cleaned, token: pasteToken)
            playCue(completeSoundName)
            let entry = TranscriptEntry(
                id: UUID().uuidString,
                createdAt: ISO8601DateFormatter.display.string(from: Date()),
                durationSeconds: duration,
                audioPath: url.path,
                rawText: raw,
                cleanedText: cleaned
            )
            try store.append(entry)
            store.setStatus("idle", "Transcript completed and copied.")
            log("Pasted transcript and copied it to clipboard.")
            log("History: \(store.htmlFile.path)")
        } catch {
            pasteController.replacePlaceholder(with: "[transcription failed]", token: pasteToken)
            store.setStatus("failed", "Transcription failed. See the launcher log for details.")
            log("Transcription failed: \(error.localizedDescription)")
        }
    }
}

struct PasteToken {
    let placeholder: String
}

final class PasteController {
    private let source = CGEventSource(stateID: .hidSystemState)

    func pastePlaceholder() -> PasteToken? {
        let token = PasteToken(placeholder: placeholderText)
        DispatchQueue.main.async {
            copyToClipboard(token.placeholder)
            sendPaste(source: self.source)
        }
        return token
    }

    func replacePlaceholder(with text: String, token: PasteToken?) {
        DispatchQueue.main.async {
            copyToClipboard(text)
            if let token {
                deletePreviousCharacters(token.placeholder.count, source: self.source)
            }
            sendPaste(source: self.source)
        }
    }
}

final class Transcriber {
    private let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    private let transcriptionModel = ProcessInfo.processInfo.environment["OPENAI_TRANSCRIBE_MODEL"] ?? "gpt-4o-mini-transcribe"
    private let cleanupModel = ProcessInfo.processInfo.environment["OPENAI_CLEANUP_MODEL"] ?? "gpt-5-mini"

    func transcribe(_ audioURL: URL) async throws -> String {
        guard !apiKey.isEmpty else { throw NSError(message: "Set OPENAI_API_KEY before running FnScribe.") }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        let boundary = "Boundary-\(UUID().uuidString)"
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let prompt = "Transcribe dictation accurately. Expect personal notes, code terms, product names, and informal speech."
        request.httpBody = try multipart(boundary: boundary, fields: [
            "model": transcriptionModel,
            "response_format": "json",
            "language": "en",
            "prompt": prompt
        ], fileField: "file", fileURL: audioURL, mimeType: "audio/mp4")

        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response: response, data: data)
        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cleanIfNeeded(_ text: String) async throws -> String {
        guard shouldClean(text) else {
            log("Cleanup skipped.")
            return text
        }
        log("Cleanup requested.")
        return try await clean(text)
    }

    private func shouldClean(_ text: String) -> Bool {
        guard !cleanupModel.isEmpty else { return false }
        switch cleanupMode.lowercased() {
        case "always":
            return true
        case "never", "off", "false", "0":
            return false
        default:
            return looksLikeItNeedsCleanup(text)
        }
    }

    private func looksLikeItNeedsCleanup(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let words = trimmed
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        if words.count <= 6 { return false }
        if words.count >= 45 { return true }
        if words.count >= 18 && !".!?".contains(trimmed.last ?? ".") { return true }

        let lower = " \(trimmed.lowercased()) "
        let cleanupSignals = [
            " um ", " uh ", " er ", " ah ",
            " you know ", " i mean ", " no wait ", " scratch that ",
            " actually ", " sorry ", " let me rephrase "
        ]
        if cleanupSignals.contains(where: { lower.contains($0) }) { return true }

        for index in words.indices.dropFirst() {
            if words[index] == words[words.index(before: index)] { return true }
        }

        let sentenceBreaks = trimmed.filter { ".!?".contains($0) }.count
        if words.count >= 28 && sentenceBreaks == 0 { return true }

        return false
    }

    func clean(_ text: String) async throws -> String {
        guard !cleanupModel.isEmpty else { return text }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ChatRequest(
            model: cleanupModel,
            messages: [
                ChatMessage(role: "system", content: "Clean up voice dictation. Preserve the user's meaning and wording. Fix punctuation, casing, paragraph breaks, and obvious transcription mistakes. Remove filler only when it is clearly not intentional. If the dictation is slightly out of order, reorganize it into the most natural sequence without adding new ideas. Return only the cleaned text."),
                ChatMessage(role: "user", content: text)
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response: response, data: data)
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }
}

enum TriggerKey {
    case fn
    case rightOption
    case rightCommand

    static func fromEnvironment() -> TriggerKey {
        switch (ProcessInfo.processInfo.environment["FNSCRIBE_TRIGGER"] ?? "fn").lowercased() {
        case "fn":
            return .fn
        case "right-command", "right-cmd", "rcmd":
            return .rightCommand
        default:
            return .rightOption
        }
    }

    var label: String {
        switch self {
        case .fn: return "Fn"
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        }
    }

    func isActive(event: CGEvent) -> Bool {
        switch self {
        case .fn:
            return event.flags.contains(.maskSecondaryFn)
        case .rightOption:
            return event.getIntegerValueField(.keyboardEventKeycode) == 61 && event.flags.contains(.maskAlternate)
        case .rightCommand:
            return event.getIntegerValueField(.keyboardEventKeycode) == 54 && event.flags.contains(.maskCommand)
        }
    }
}

final class KeyWatcher {
    private let recorder: Recorder
    private let trigger: TriggerKey
    private var triggerDown = false
    private var pendingHold: DispatchWorkItem?
    private var lastTapAt = Date.distantPast
    private var longMode = false

    init(recorder: Recorder, trigger: TriggerKey) {
        self.recorder = recorder
        self.trigger = trigger
    }

    func handle(_ event: CGEvent) {
        let isTrigger = trigger.isActive(event: event)
        if isTrigger && !triggerDown {
            triggerDown = true
            onTriggerDown()
        } else if !isTrigger && triggerDown {
            triggerDown = false
            onTriggerUp()
        }
    }

    private func onTriggerDown() {
        let now = Date()
        if now.timeIntervalSince(lastTapAt) <= doubleTapWindow {
            lastTapAt = .distantPast
            pendingHold?.cancel()
            toggleLongMode()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.triggerDown, !self.longMode else { return }
            self.recorder.start(mode: "hold")
        }
        pendingHold = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: work)
    }

    private func onTriggerUp() {
        if recorder.isRecording && !longMode {
            recorder.stop()
            return
        }
        if pendingHold?.isCancelled == false {
            pendingHold?.cancel()
            lastTapAt = Date()
        }
    }

    private func toggleLongMode() {
        if longMode {
            longMode = false
            recorder.stop()
        } else {
            longMode = true
            recorder.start(mode: "long")
        }
    }
}

struct TranscriptionResponse: Decodable {
    let text: String
}

struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatResponse: Decodable {
    struct Choice: Decodable {
        let message: ChatMessage
    }
    let choices: [Choice]
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension ISO8601DateFormatter {
    static var fileSafe: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    static var display: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

extension NSError {
    convenience init(message: String) {
        self.init(domain: appName, code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

func multipart(boundary: String, fields: [String: String], fileField: String, fileURL: URL, mimeType: String) throws -> Data {
    var data = Data()
    for (key, value) in fields {
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
        data.append("\(value)\r\n")
    }
    data.append("--\(boundary)\r\n")
    data.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
    data.append("Content-Type: \(mimeType)\r\n\r\n")
    data.append(try Data(contentsOf: fileURL))
    data.append("\r\n--\(boundary)--\r\n")
    return data
}

func check(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(message: body)
    }
}

func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

func sendPaste(source: CGEventSource?) {
    sendModifiedKey(keyCode: 9, flags: .maskCommand, source: source)
}

func deletePreviousCharacters(_ count: Int, source: CGEventSource?) {
    guard count > 0 else { return }
    for _ in 0..<count {
        sendModifiedKey(keyCode: 51, flags: [], source: source)
        usleep(1_000)
    }
}

func sendModifiedKey(keyCode: CGKeyCode, flags: CGEventFlags, source: CGEventSource?) {
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
        return
    }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

func playCue(_ name: String) {
    guard soundEnabled else { return }
    DispatchQueue.main.async {
        guard let sound = NSSound(named: NSSound.Name(name)) else {
            log("Sound cue not found: \(name)")
            return
        }
        activeSounds.append(sound)
        sound.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            activeSounds.removeAll { $0 === sound }
        }
    }
}

func escape(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

func escapeAttribute(_ text: String) -> String {
    escape(text).replacingOccurrences(of: "'", with: "&#039;")
}

extension Data {
    mutating func append(_ string: String) {
        append(string.data(using: .utf8)!)
    }
}

func log(_ message: String) {
    let line = "\(ISO8601DateFormatter.display.string(from: Date())) \(message)\n"
    print(message)
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile.path),
           let handle = try? FileHandle(forWritingTo: logFile) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: logFile)
        }
    }
}

func installKeyboardTap(watcher: KeyWatcher) {
    let mask = (1 << CGEventType.flagsChanged.rawValue)
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: CGEventMask(mask),
        callback: { _, _, event, refcon in
            let watcher = Unmanaged<KeyWatcher>.fromOpaque(refcon!).takeUnretainedValue()
            watcher.handle(event)
            return Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(watcher).toOpaque()
    ) else {
        log("Could not create keyboard event tap. Enable Accessibility access for Terminal or FnScribe, then run again.")
        exit(1)
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    log("FnScribe is running.")
    log("Hold \(triggerKey.label) to record. Double-tap \(triggerKey.label) to start/stop long recording.")
    log("History UI: \(store.htmlFile.path)")
    CFRunLoopRun()
}

let store = try Store()
store.setStatus("idle", "Ready")
try store.renderHTML(store.load(), status: store.loadStatus())

if CommandLine.arguments.contains("--smoke-test") {
    log("Smoke test passed.")
    log("History UI: \(store.htmlFile.path)")
    exit(0)
}

log("FnScribe starting.")
let transcriber = Transcriber()
let recorder = Recorder(store: store, transcriber: transcriber)
let watcher = KeyWatcher(recorder: recorder, trigger: triggerKey)

AVCaptureDevice.requestAccess(for: .audio) { granted in
    if !granted {
        log("Microphone access was not granted. Enable it in System Settings.")
        exit(1)
    }
    log("Microphone access granted.")
    installKeyboardTap(watcher: watcher)
}

CFRunLoopRun()

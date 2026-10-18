import AppKit
#if SWIFT_PACKAGE
import VoiceSnippets
#endif

final class VoiceSnippetRow: NSStackView {
    let enabled = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    let trigger = NSTextField()
    let text = NSTextView()
    let deleteButton = NSButton(title: "Delete", target: nil, action: nil)

    init(snippet: VoiceSnippet) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 6
        trigger.placeholderString = "Spoken trigger phrase"
        trigger.stringValue = snippet.trigger
        trigger.setAccessibilityLabel("Spoken trigger phrase")
        enabled.state = snippet.enabled ? .on : .off
        let header = NSStackView(views: [enabled, trigger, deleteButton])
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(header)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.string = snippet.text
        text.setAccessibilityLabel("Snippet replacement text")
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.minSize = NSSize(width: 0, height: 90)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.frame = NSRect(x: 0, y: 0, width: 600, height: 90)
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(scroll)
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: widthAnchor),
            scroll.widthAnchor.constraint(equalTo: widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 90)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var snippet: VoiceSnippet {
        VoiceSnippet(trigger: trigger.stringValue, text: text.string, enabled: enabled.state == .on)
    }
}

final class VoiceSnippetsSettingsController: NSWindowController {
    private let store: VoiceSnippetStore
    private var snapshot: VoiceSnippetSnapshot?
    private let enabled = NSButton(checkboxWithTitle: "Enable Voice Snippets", target: nil, action: nil)
    private let rowsStack = NSStackView()
    private var rows: [VoiceSnippetRow] = []
    private let feedback = NSTextField(wrappingLabelWithString: "")

    init(store: VoiceSnippetStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Settings — Voice Snippets"
        window.minSize = NSSize(width: 580, height: 480)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildContent()
        reload()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let path = NSTextField(wrappingLabelWithString: store.url.path)
        path.isSelectable = true
        path.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let instructions = NSTextField(wrappingLabelWithString:
            "Create spoken phrases and their replacement text below. Save applies all edits. Reload discards unsaved edits and reads the JSON file. External edits apply to the next transcription.")
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 16
        rowsStack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = rowsStack
        NSLayoutConstraint.activate([
            rowsStack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            rowsStack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            rowsStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        let add = NSButton(title: "Add Snippet", target: self, action: #selector(addSnippet))
        let reload = NSButton(title: "Reload", target: self, action: #selector(reload))
        let reveal = NSButton(title: "Reveal Config File", target: self, action: #selector(revealConfig))
        let save = NSButton(title: "Save", target: self, action: #selector(save))
        let buttons = NSStackView(views: [add, reload, reveal, save])
        buttons.spacing = 8
        feedback.isSelectable = true
        let stack = NSStackView(views: [enabled, instructions, path, scroll, feedback, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            instructions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            path.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            feedback.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func appendRow(_ snippet: VoiceSnippet) {
        let row = VoiceSnippetRow(snippet: snippet)
        row.deleteButton.target = self
        row.deleteButton.action = #selector(deleteSnippet(_:))
        rows.append(row)
        rowsStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor, constant: -20).isActive = true
    }

    @objc private func addSnippet() {
        appendRow(VoiceSnippet(trigger: "", text: ""))
        if let row = rows.last {
            row.scrollToVisible(row.bounds)
            window?.makeFirstResponder(row.trigger)
        }
    }

    @objc private func deleteSnippet(_ sender: NSButton) {
        guard let index = rows.firstIndex(where: { $0.deleteButton === sender }) else { return }
        let row = rows.remove(at: index)
        rowsStack.removeArrangedSubview(row)
        row.removeFromSuperview()
    }

    @objc private func reload() {
        do {
            let loaded = try store.load()
            snapshot = loaded
            enabled.state = loaded.configuration.enabled ? .on : .off
            for row in rows {
                rowsStack.removeArrangedSubview(row)
                row.removeFromSuperview()
            }
            rows = []
            for snippet in loaded.configuration.snippets { appendRow(snippet) }
            showFeedback("Loaded \(rows.count) snippets. Save to persist changes.", error: false)
        } catch {
            showFeedback(error.localizedDescription, error: true)
        }
    }

    @objc private func save() {
        guard let snapshot else {
            showFeedback("Fix the configuration file and Reload before saving. Your draft has not been discarded.", error: true)
            return
        }
        do {
            let configuration = VoiceSnippetConfiguration(enabled: enabled.state == .on, snippets: rows.map(\.snippet))
            self.snapshot = try store.save(configuration, replacing: snapshot)
            showFeedback("Saved. Changes apply to the next transcription.", error: false)
        } catch {
            showFeedback(error.localizedDescription, error: true)
        }
    }

    @objc private func revealConfig() {
        if FileManager.default.fileExists(atPath: store.url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([store.url])
        } else {
            showFeedback("Save first to create \(store.url.path).", error: false)
        }
    }

    private func showFeedback(_ message: String, error: Bool) {
        feedback.stringValue = message
        feedback.textColor = error ? .systemRed : .secondaryLabelColor
    }
}

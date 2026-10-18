import Foundation

public struct VoiceSnippet: Codable, Equatable, Sendable {
    public var trigger: String
    public var text: String
    public var enabled: Bool

    public init(trigger: String, text: String, enabled: Bool = true) {
        self.trigger = trigger
        self.text = text
        self.enabled = enabled
    }
}

public struct VoiceSnippetConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var snippets: [VoiceSnippet]

    public init(enabled: Bool = true, snippets: [VoiceSnippet] = []) {
        self.enabled = enabled
        self.snippets = snippets
    }

    public func validate() throws {
        var triggers = Set<String>()
        for (index, snippet) in snippets.enumerated() {
            let trigger = snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trigger.isEmpty, trigger == snippet.trigger,
                  trigger.rangeOfCharacter(from: .newlines) == nil else {
                throw VoiceSnippetError("Snippet \(index + 1): enter a nonempty, single-line trigger without leading or trailing whitespace.")
            }
            guard triggers.insert(Self.key(trigger)).inserted else {
                throw VoiceSnippetError("Snippet \(index + 1): duplicate trigger “\(trigger)” (triggers ignore case and whitespace).")
            }
        }
    }

    private static func key(_ trigger: String) -> String {
        trigger.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    public func expand(_ text: String) -> String {
        guard enabled else { return text }
        let ordered = snippets.enumerated().filter { $0.element.enabled }.sorted {
            if $0.element.trigger.count != $1.element.trigger.count {
                return $0.element.trigger.count > $1.element.trigger.count
            }
            return $0.offset < $1.offset
        }
        guard !ordered.isEmpty else { return text }
        // One pass over the original text: inserted snippets are never expanded again.
        let patterns = ordered.map { item in
            item.element.trigger.split(whereSeparator: { $0.isWhitespace })
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: "\\s+")
        }
        let alternatives = patterns.map { "(\($0))" }.joined(separator: "|")
        guard let regex = try? NSRegularExpression(
            pattern: "(?<![\\p{L}\\p{M}\\p{N}_])(?:\(alternatives))(?![\\p{L}\\p{M}\\p{N}_])",
            options: .caseInsensitive
        ) else { return text }
        let source = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        var result = ""
        var cursor = 0
        for match in matches {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            for (index, item) in ordered.enumerated() where match.range(at: index + 1).location != NSNotFound {
                result += item.element.text
                break
            }
            cursor = NSMaxRange(match.range)
        }
        result += source.substring(from: cursor)
        return result
    }
}

public struct VoiceSnippetError: LocalizedError {
    public let errorDescription: String?

    public init(_ message: String) {
        errorDescription = message
    }
}

public struct VoiceSnippetSnapshot: Sendable {
    public let configuration: VoiceSnippetConfiguration
    public let data: Data?
}

public final class VoiceSnippetStore: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    private var cached = VoiceSnippetConfiguration()

    public init(url: URL) {
        self.url = url
    }

    public static func configurationURL(projectRoot: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let home: URL
        if let override = environment["FNSCRIBE_HOME"], !override.isEmpty {
            home = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            home = projectRoot.appendingPathComponent("work/fn-scribe-store", isDirectory: true)
        }
        return home.appendingPathComponent("voice-snippets.json")
    }

    private func readData() throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }

    public func load() throws -> VoiceSnippetSnapshot {
        lock.lock()
        defer { lock.unlock() }
        do {
            let data = try readData()
            let configuration = try data.map { try JSONDecoder().decode(VoiceSnippetConfiguration.self, from: $0) }
                ?? VoiceSnippetConfiguration()
            try configuration.validate()
            cached = configuration
            return VoiceSnippetSnapshot(configuration: configuration, data: data)
        } catch {
            throw VoiceSnippetError("Could not load \(url.path): \(Self.describe(error)) The file was not changed. Fix it and reload; dictation keeps the last valid snippets.")
        }
    }

    private static func describe(_ error: Error) -> String {
        let context: DecodingError.Context
        let message: String
        switch error {
        case DecodingError.keyNotFound(let key, let details):
            context = details
            message = "Missing required field “\(key.stringValue)”."
        case DecodingError.typeMismatch(_, let details), DecodingError.valueNotFound(_, let details):
            context = details
            message = "Invalid field value. \(details.debugDescription)"
        case DecodingError.dataCorrupted(let details):
            context = details
            message = "Invalid JSON. \(details.debugDescription)"
        default:
            return error.localizedDescription
        }
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? message : "\(path): \(message)"
    }

    public func expandUsingLastValidConfiguration(_ text: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return cached.expand(text)
    }

    @discardableResult
    public func save(_ configuration: VoiceSnippetConfiguration, replacing snapshot: VoiceSnippetSnapshot) throws -> VoiceSnippetSnapshot {
        lock.lock()
        defer { lock.unlock() }
        try configuration.validate()
        guard try readData() == snapshot.data else {
            throw VoiceSnippetError("The snippets file changed outside Settings. Reload before saving to avoid overwriting external edits.")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(configuration)
        data.append(0x0A)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        cached = configuration
        return VoiceSnippetSnapshot(configuration: configuration, data: data)
    }
}

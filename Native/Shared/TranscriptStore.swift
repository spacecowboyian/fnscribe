import Foundation

struct TranscriptEntry: Codable, Identifiable, Hashable {
    let id: String
    let createdAt: String
    let durationSeconds: Double
    let audioPath: String
    let rawText: String
    let cleanedText: String
}

enum TranscriptStore {
    static let projectRoot = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["FNSCRIBE_PROJECT_ROOT"] ?? FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    static let historyURL = projectRoot.appendingPathComponent("public/history.json")
    static let statusURL = projectRoot.appendingPathComponent("public/status.json")

    static func load(limit: Int = 5) -> [TranscriptEntry] {
        guard let data = try? Data(contentsOf: historyURL),
              let entries = try? JSONDecoder().decode([TranscriptEntry].self, from: data) else {
            return []
        }
        return Array(entries.prefix(limit))
    }
}

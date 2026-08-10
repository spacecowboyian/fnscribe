import AppIntents
import AppKit
import SwiftUI
import WidgetKit

struct RecentEntry: TimelineEntry {
    let date: Date
    let transcripts: [TranscriptEntry]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> RecentEntry {
        RecentEntry(date: Date(), transcripts: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentEntry) -> Void) {
        completion(RecentEntry(date: Date(), transcripts: TranscriptStore.load(limit: 5)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentEntry>) -> Void) {
        let entry = RecentEntry(date: Date(), transcripts: TranscriptStore.load(limit: 5))
        let next = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date().addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct CopyTranscriptIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Transcript"

    @Parameter(title: "Text")
    var text: String

    init() {
        text = ""
    }

    init(text: String) {
        self.text = text
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        return .result()
    }
}

struct FnScribeRecentWidgetView: View {
    let entry: RecentEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FnScribe")
                .font(.headline)

            if entry.transcripts.isEmpty {
                Text("No transcripts yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.transcripts.prefix(5)) { transcript in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transcript.cleanedText)
                            .font(.caption)
                            .lineLimit(3)
                        HStack {
                            Text(durationLabel(transcript.durationSeconds))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(intent: CopyTranscriptIntent(text: transcript.cleanedText)) {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)

                    if transcript.id != entry.transcripts.prefix(5).last?.id {
                        Divider()
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    func durationLabel(_ seconds: Double) -> String {
        "\(Int(seconds.rounded()))s"
    }
}

struct FnScribeRecentWidget: Widget {
    let kind = "FnScribeRecentWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            FnScribeRecentWidgetView(entry: entry)
        }
        .configurationDisplayName("FnScribe Recent")
        .description("Shows your latest FnScribe transcripts.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct FnScribeWidgetBundle: WidgetBundle {
    var body: some Widget {
        FnScribeRecentWidget()
    }
}

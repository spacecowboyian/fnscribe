import AppKit
import SwiftUI

@main
struct FnScribeWidgetHostApp: App {
    var body: some Scene {
        WindowGroup("FnScribe Recent") {
            RecentTranscriptsView()
                .frame(minWidth: 360, minHeight: 420)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

struct RecentTranscriptsView: View {
    @State private var entries = TranscriptStore.load(limit: 10)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("FnScribe")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh") {
                    entries = TranscriptStore.load(limit: 10)
                }
            }

            if entries.isEmpty {
                ContentUnavailableView("No Transcripts", systemImage: "text.bubble")
            } else {
                List(entries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.cleanedText)
                            .lineLimit(4)
                        HStack {
                            Text(entry.createdAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.cleanedText, forType: .string)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding()
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            entries = TranscriptStore.load(limit: 10)
        }
    }
}

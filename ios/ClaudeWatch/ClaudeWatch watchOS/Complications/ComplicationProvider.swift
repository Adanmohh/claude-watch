import WidgetKit
import SwiftUI

// MARK: - Agent Watch Complication (WidgetKit)

/// Timeline entry representing the current state of the Claude session.
struct ClaudeWatchEntry: TimelineEntry {
    let date: Date
    let lastOutputLine: String
    let status: Status

    enum Status: String {
        case idle = "Idle"
        case running = "Running"
        case offline = "Offline"

        var color: Color {
            switch self {
            case .idle: return Palette.accent
            case .running: return Palette.success
            case .offline: return Palette.danger
            }
        }
    }

    static var placeholder: ClaudeWatchEntry {
        ClaudeWatchEntry(
            date: Date(),
            lastOutputLine: "Ready",
            status: .idle
        )
    }
}

// MARK: - Timeline Provider

struct ClaudeWatchTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClaudeWatchEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ClaudeWatchEntry) -> Void) {
        let entry = currentEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudeWatchEntry>) -> Void) {
        let entry = currentEntry()
        // Refresh every 5 minutes when idle, every 30 seconds when running
        let refreshInterval: TimeInterval = entry.status == .running ? 30 : 300
        let nextUpdate = Date().addingTimeInterval(refreshInterval)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func currentEntry() -> ClaudeWatchEntry {
        let session = WatchViewState.shared

        let status: ClaudeWatchEntry.Status
        switch session.sessionState.connection {
        case .disconnected:
            status = .offline
        case .connected where session.sessionState.activity == .running:
            status = .running
        default:
            status = .idle
        }

        let lastLine = session.terminalLines.last?.text ?? "No output"

        return ClaudeWatchEntry(
            date: Date(),
            lastOutputLine: String(lastLine.prefix(50)),
            status: status
        )
    }
}

// MARK: - Rectangular Complication View

struct ClaudeWatchRectangularView: View {
    let entry: ClaudeWatchEntry

    var body: some View {
        HStack(spacing: 8) {
            // Signature block glyph, colored by session state.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(entry.status.color)
                .frame(width: 8, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.status.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(entry.status.color)

                Text(entry.lastOutputLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .widgetURL(URL(string: "claudewatch://session"))
    }
}

// MARK: - Widget Definition
// Note: @main belongs on this struct when it lives in its own Widget Extension target.
// If sharing the same target as the app, remove @main and register via WidgetBundle.

struct ClaudeWatchComplication: Widget {
    let kind = "ClaudeWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeWatchTimelineProvider()) { entry in
            ClaudeWatchRectangularView(entry: entry)
                .containerBackground(Theme.Background.primary, for: .widget)
        }
        .configurationDisplayName("ClaudeWatch")
        .description("Shows Claude session status and latest output.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Preview

#Preview(as: .accessoryRectangular) {
    ClaudeWatchComplication()
} timeline: {
    ClaudeWatchEntry(date: Date(), lastOutputLine: "Build succeeded", status: .idle)
    ClaudeWatchEntry(date: Date(), lastOutputLine: "Installing deps...", status: .running)
    ClaudeWatchEntry(date: Date(), lastOutputLine: "---", status: .offline)
}

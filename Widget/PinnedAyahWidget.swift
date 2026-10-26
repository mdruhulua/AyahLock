import AppIntents
import SwiftUI
import WidgetKit

struct PinnedEntry: TimelineEntry {
    let date: Date
    let item: RecitationItem?
    let settings: PlaybackSettings
}

struct PinnedProvider: TimelineProvider {
    func placeholder(in context: Context) -> PinnedEntry {
        PinnedEntry(date: .now, item: nil, settings: PlaybackSettings())
    }

    func getSnapshot(in context: Context, completion: @escaping (PinnedEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PinnedEntry>) -> Void) {
        // The app reloads the widget whenever you pin something new.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> PinnedEntry {
        let store = SharedStore.shared
        return PinnedEntry(date: .now, item: store.pinned, settings: store.settings)
    }
}

/// The lock-screen (and home-screen) widget showing the pinned ayah/dua with a play button.
struct PinnedAyahWidget: Widget {
    let kind = "PinnedAyahWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PinnedProvider()) { entry in
            PinnedAyahWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pinned Ayah/Dua")
        .description("Shows your pinned ayah or dua. Tap play to recite it on repeat.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .systemSmall, .systemMedium])
    }
}

struct PinnedAyahWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PinnedEntry

    var body: some View {
        if let item = entry.item {
            switch family {
            case .accessoryInline:
                Text(item.title)
            case .accessoryCircular:
                Button(intent: PlayRecitationIntent()) {
                    ZStack {
                        AccessoryWidgetBackground()
                        Image(systemName: "play.fill").font(.title3)
                    }
                }
                .buttonStyle(.plain)
            case .accessoryRectangular:
                HStack(spacing: 6) {
                    Button(intent: PlayRecitationIntent()) {
                        Image(systemName: "play.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(item.arabic)
                            .font(.system(size: 13))
                            .lineLimit(meaning(for: item) == nil ? 3 : 2)
                            .multilineTextAlignment(.trailing)
                        if let meaning = meaning(for: item) {
                            Text(meaning).font(.system(size: 10)).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            default:
                VStack(alignment: .trailing, spacing: 6) {
                    Text(item.arabic)
                        .font(.system(size: family == .systemSmall ? 15 : 18))
                        .multilineTextAlignment(.trailing)
                        .lineLimit(family == .systemSmall ? 4 : 3)
                    if family == .systemMedium, let meaning = meaning(for: item) {
                        Text(meaning).font(.caption).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Text(item.title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button(intent: PlayRecitationIntent()) {
                            Image(systemName: "play.circle.fill").font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            Text(family == .accessoryInline ? "Pin an ayah in AyahLock" : "Open AyahLock and pin an ayah or dua")
                .font(.caption)
        }
    }

    /// The first meaning switched on in settings (lock-screen space fits one).
    private func meaning(for item: RecitationItem) -> String? {
        if entry.settings.showBengali, !item.bengali.isEmpty { return item.bengali }
        if entry.settings.showEnglish, !item.english.isEmpty { return item.english }
        return nil
    }
}

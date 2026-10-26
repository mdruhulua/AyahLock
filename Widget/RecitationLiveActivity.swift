import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The lock-screen panel shown while reciting: full text, meanings, counter, stop.
struct RecitationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecitationActivityAttributes.self) { context in
            LockScreenRecitationView(context: context)
                .padding()
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.counterText, systemImage: "repeat")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: StopRecitationIntent()) {
                        Image(systemName: "stop.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.arabic)
                        .font(.system(size: 15))
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } compactLeading: {
                Image(systemName: "book.closed.fill")
            } compactTrailing: {
                Text(context.state.counterText).font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "repeat")
            }
        }
    }
}

struct LockScreenRecitationView: View {
    let context: ActivityViewContext<RecitationActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(context.attributes.title).font(.headline).lineLimit(1)
                Spacer()
                Text(context.state.counterText).font(.subheadline.monospacedDigit())
                Button(intent: StopRecitationIntent()) {
                    Image(systemName: "stop.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
            }
            Text(context.attributes.arabic)
                .font(.system(size: 18))
                .lineLimit(3)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if let bengali = context.attributes.bengali {
                Text(bengali).font(.caption).lineLimit(2)
            }
            if let english = context.attributes.english {
                Text(english).font(.caption).lineLimit(2)
            }
        }
    }
}

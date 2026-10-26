import AppIntents
import Foundation

// These intents are compiled into both the app and the widget, because the
// widget's buttons need to reference them. Because they are audio intents,
// iOS runs perform() inside the app's process, where the player lives.
// The widget build defines WIDGET_EXTENSION, so it skips the player calls.

/// Plays the pinned ayah/dua with your repeat settings.
struct PlayRecitationIntent: AudioPlaybackIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Recite pinned ayah or dua"
    static var description = IntentDescription("Plays the pinned ayah or dua with your repeat settings.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await RecitationPlayer.shared.togglePinned()
        #endif
        return .result()
    }
}

/// Stops the recitation.
struct StopRecitationIntent: AudioPlaybackIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop recitation"

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await RecitationPlayer.shared.stop()
        #endif
        return .result()
    }
}

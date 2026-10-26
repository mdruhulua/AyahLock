import ActivityKit
import Foundation

/// Data for the Live Activity shown on the lock screen while reciting.
/// Texts are clipped because Live Activity data has a small size limit.
struct RecitationActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var currentRepeat: Int
        var totalRepeats: Int   // 0 = until stopped
        var isPlaying: Bool

        var counterText: String {
            totalRepeats == 0 ? "Repeat \(currentRepeat)" : "\(currentRepeat) of \(totalRepeats)"
        }
    }

    var title: String
    var arabic: String
    var english: String?
    var bengali: String?
}

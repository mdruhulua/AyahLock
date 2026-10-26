import Foundation

/// The App Group shared by the app and the widget.
/// Must match the entitlements in project.yml (rename.sh changes both).
enum AppGroup {
    static let id = "group.com.example.ayahlock"
}

/// Storage both the app and the widget can read.
final class SharedStore {
    static let shared = SharedStore()

    private let defaults: UserDefaults
    let containerURL: URL

    private enum Key {
        static let library = "library"
        static let pinnedID = "pinnedID"
        static let settings = "settings"
    }

    init() {
        defaults = UserDefaults(suiteName: AppGroup.id) ?? .standard
        containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var audioDirectory: URL {
        let dir = containerURL.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var library: [RecitationItem] {
        get { decode([RecitationItem].self, Key.library) ?? [] }
        set { encode(newValue, Key.library) }
    }

    var pinnedID: UUID? {
        get { defaults.string(forKey: Key.pinnedID).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.pinnedID) }
    }

    var pinned: RecitationItem? {
        guard let id = pinnedID else { return nil }
        return library.first { $0.id == id }
    }

    var settings: PlaybackSettings {
        get { decode(PlaybackSettings.self, Key.settings) ?? PlaybackSettings() }
        set { encode(newValue, Key.settings) }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}

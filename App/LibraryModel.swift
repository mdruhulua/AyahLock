import Foundation
import WidgetKit

/// The app's view of your saved items, pinned item and settings.
/// Every change is saved to the shared store and the widget is refreshed.
@MainActor
final class LibraryModel: ObservableObject {
    @Published var items: [RecitationItem] { didSet { save() } }
    @Published var pinnedID: UUID? { didSet { save() } }
    @Published var settings: PlaybackSettings { didSet { save() } }

    private let store = SharedStore.shared

    init() {
        items = store.library
        pinnedID = store.pinnedID
        settings = store.settings
    }

    var pinned: RecitationItem? { items.first { $0.id == pinnedID } }

    func add(_ item: RecitationItem, pin: Bool = true) {
        items.insert(item, at: 0)
        if pin { pinnedID = item.id }
    }

    func pin(_ item: RecitationItem) {
        pinnedID = item.id
    }

    func delete(at offsets: IndexSet) {
        let removed = offsets.map { items[$0] }
        items.remove(atOffsets: offsets)
        if let id = pinnedID, removed.contains(where: { $0.id == id }) {
            pinnedID = items.first?.id
        }
        // Delete audio files no remaining item uses.
        let stillUsed = Set(items.flatMap(\.audioFileNames))
        for file in removed.flatMap(\.audioFileNames) where !stillUsed.contains(file) {
            try? FileManager.default.removeItem(at: store.audioDirectory.appendingPathComponent(file))
        }
    }

    private func save() {
        store.library = items
        store.pinnedID = pinnedID
        store.settings = settings
        WidgetCenter.shared.reloadAllTimelines()
    }
}

import Foundation

/// A saved ayah with your own note.
struct Bookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    var surah: Int
    var ayah: Int
    var note: String
    var created: Date
    var updated: Date

    var ref: QuranTextStore.AyahRef { .init(surah: surah, ayah: ayah) }
    var title: String { "\(Surah.all[surah - 1].name) \(surah):\(ayah)" }
}

/// Your bookmarks, saved in a file on the phone (one bookmark per ayah).
@MainActor
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()

    enum Order: String, CaseIterable, Identifiable {
        case quran = "Quran order"
        case recent = "Recently changed"
        var id: String { rawValue }
    }

    @Published private(set) var bookmarks: [Bookmark] = []
    private let fileURL: URL

    init(fileURL: URL = SharedStore.shared.containerURL.appendingPathComponent("Bookmarks.json")) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = saved
        }
    }

    func bookmark(surah: Int, ayah: Int) -> Bookmark? {
        bookmarks.first { $0.surah == surah && $0.ayah == ayah }
    }

    func isBookmarked(surah: Int, ayah: Int) -> Bool {
        bookmark(surah: surah, ayah: ayah) != nil
    }

    /// Adds a bookmark, or updates the note if the ayah is already bookmarked.
    @discardableResult
    func save(surah: Int, ayah: Int, note: String) -> Bookmark {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        if let index = bookmarks.firstIndex(where: { $0.surah == surah && $0.ayah == ayah }) {
            bookmarks[index].note = trimmed
            bookmarks[index].updated = now
            persist()
            return bookmarks[index]
        }
        let new = Bookmark(surah: surah, ayah: ayah, note: trimmed, created: now, updated: now)
        bookmarks.append(new)
        persist()
        return new
    }

    func delete(surah: Int, ayah: Int) {
        bookmarks.removeAll { $0.surah == surah && $0.ayah == ayah }
        persist()
    }

    func delete(ids: [UUID]) {
        bookmarks.removeAll { ids.contains($0.id) }
        persist()
    }

    func sorted(_ order: Order) -> [Bookmark] {
        switch order {
        case .quran: return bookmarks.sorted { ($0.surah, $0.ayah) < ($1.surah, $1.ayah) }
        case .recent: return bookmarks.sorted { $0.updated > $1.updated }
        }
    }

    /// Bookmarks whose note or surah name contains the text.
    func filtered(_ query: String, order: Order) -> [Bookmark] {
        let q = QuranTextStore.fold(query.trimmingCharacters(in: .whitespaces))
        let all = sorted(order)
        guard !q.isEmpty else { return all }
        return all.filter { QuranTextStore.fold($0.note + " " + $0.title).contains(q) }
    }

    /// All bookmarks with their notes as plain text, for sharing or backup.
    func exportText(store: QuranTextStore) -> String {
        var lines = ["AyahLock bookmarks (\(bookmarks.count))", ""]
        for b in sorted(.quran) {
            lines.append("• \(b.title)")
            let arabic = store.arabic(b.surah, b.ayah)
            if !arabic.isEmpty { lines.append(arabic) }
            let english = store.english(b.surah, b.ayah)
            if !english.isEmpty { lines.append(english) }
            if !b.note.isEmpty { lines.append("Note: \(b.note)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

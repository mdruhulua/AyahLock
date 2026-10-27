import Foundation

/// A tafsir (explanation of the Quran) you can read beside any ayah.
struct TafsirSource: Identifiable, Hashable {
    let slug: String
    let name: String
    let author: String
    let language: String   // "English" or "Bengali"
    var id: String { slug }

    static let all: [TafsirSource] = [
        TafsirSource(slug: "en-tafisr-ibn-kathir", name: "Ibn Kathir (abridged)", author: "Hafiz Ibn Kathir", language: "English"),
        TafsirSource(slug: "en-tafsir-maarif-ul-quran", name: "Ma'ariful Qur'an", author: "Mufti Muhammad Shafi", language: "English"),
        TafsirSource(slug: "bn-tafsir-ahsanul-bayaan", name: "Tafsir Ahsanul Bayaan", author: "Bayaan Foundation", language: "Bengali"),
        TafsirSource(slug: "bn-tafsir-abu-bakr-zakaria", name: "Tafsir Abu Bakr Zakaria", author: "Dr. Abu Bakr Zakaria", language: "Bengali"),
        TafsirSource(slug: "bn-tafseer-ibn-e-kaseer", name: "Tafsir Ibn Kathir (Bengali)", author: "Tawheed Publication", language: "Bengali"),
    ]

    static func named(_ slug: String) -> TafsirSource {
        all.first { $0.slug == slug } ?? all[0]
    }
}

/// The explanation for one ayah. Some tafsirs explain several ayahs together;
/// `fromAyah`–`toAyah` is the group this text covers.
struct TafsirEntry: Equatable {
    let text: String
    let fromAyah: Int
    let toAyah: Int
}

/// Fetches tafsir one surah at a time and keeps it on the phone, so each
/// surah is downloaded once and then reads offline.
@MainActor
final class TafsirStore: ObservableObject {
    static let shared = TafsirStore()

    struct FullDownload: Equatable {
        let slug: String
        var done: Int
        let total = 114
    }

    @Published private(set) var fullDownload: FullDownload?
    @Published private(set) var lastError: String?

    private var memory: [String: [String]] = [:]   // "slug/surah" → text per ayah
    private var downloadTask: Task<Void, Never>?
    private let directory: URL

    init(directory: URL = SharedStore.shared.containerURL.appendingPathComponent("Tafsir", isDirectory: true)) {
        self.directory = directory
    }

    // MARK: Reading

    func entry(slug: String, surah: Int, ayah: Int) async throws -> TafsirEntry {
        let texts = try await surahTexts(slug: slug, surah: surah)
        return Self.group(texts, ayah: ayah)
    }

    /// The text of every ayah in a surah, from memory, the phone, or the internet.
    func surahTexts(slug: String, surah: Int) async throws -> [String] {
        let key = "\(slug)/\(surah)"
        if let cached = memory[key] { return cached }
        if let data = try? Data(contentsOf: fileURL(slug: slug, surah: surah)),
           let saved = try? JSONDecoder().decode([String].self, from: data),
           saved.count == Surah.all[surah - 1].ayahCount {
            memory[key] = saved
            return saved
        }
        let texts = try await Self.fetch(slug: slug, surah: surah)
        save(texts, slug: slug, surah: surah)
        memory[key] = texts
        return texts
    }

    /// Finds the run of neighbouring ayahs that share the same explanation.
    nonisolated static func group(_ texts: [String], ayah: Int) -> TafsirEntry {
        guard ayah >= 1, ayah <= texts.count else { return TafsirEntry(text: "", fromAyah: ayah, toAyah: ayah) }
        let text = texts[ayah - 1]
        var from = ayah
        var to = ayah
        if !text.isEmpty {
            while from > 1 && texts[from - 2] == text { from -= 1 }
            while to < texts.count && texts[to] == text { to += 1 }
        }
        return TafsirEntry(text: text, fromAyah: from, toAyah: to)
    }

    // MARK: Offline

    func isSaved(slug: String, surah: Int) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(slug: slug, surah: surah).path)
    }

    func savedSurahCount(slug: String) -> Int {
        (1...114).filter { isSaved(slug: slug, surah: $0) }.count
    }

    /// Saves all 114 surahs of a tafsir for offline reading.
    func downloadAll(slug: String) {
        guard fullDownload == nil else { return }
        lastError = nil
        fullDownload = FullDownload(slug: slug, done: savedSurahCount(slug: slug))
        downloadTask = Task {
            for surah in 1...114 {
                if Task.isCancelled { break }
                if isSaved(slug: slug, surah: surah) { continue }
                do {
                    let texts = try await Self.fetch(slug: slug, surah: surah)
                    save(texts, slug: slug, surah: surah)
                    fullDownload?.done = savedSurahCount(slug: slug)
                } catch {
                    lastError = "Download stopped at surah \(surah): \(error.localizedDescription)"
                    break
                }
            }
            fullDownload = nil
            downloadTask = nil
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func deleteAll(slug: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(slug, isDirectory: true))
        memory = memory.filter { !$0.key.hasPrefix(slug + "/") }
        objectWillChange.send()
    }

    // MARK: Files and network

    private func fileURL(slug: String, surah: Int) -> URL {
        directory.appendingPathComponent(slug, isDirectory: true).appendingPathComponent("\(surah).json")
    }

    private func save(_ texts: [String], slug: String, surah: Int) {
        let url = fileURL(slug: slug, surah: surah)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(texts) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private struct Row: Decodable {
        let text: String?
        let ayah: Int
    }

    /// Two copies of the same open dataset (spa5k/tafsir_api); the second is used if the first fails.
    nonisolated static func urls(slug: String, surah: Int) -> [URL] {
        [
            "https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir/\(slug)/\(surah).json",
            "https://raw.githubusercontent.com/spa5k/tafsir_api/main/tafsir/\(slug)/\(surah).json",
        ].compactMap(URL.init(string:))
    }

    nonisolated static func fetch(slug: String, surah: Int) async throws -> [String] {
        let count = Surah.all[surah - 1].ayahCount
        var lastError: Error = QuranAPI.APIError.server("no source")
        for url in urls(slug: slug, surah: surah) {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw QuranAPI.APIError.server("HTTP \(http.statusCode)")
                }
                let rows = try JSONDecoder().decode([Row].self, from: data)
                var texts = Array(repeating: "", count: count)
                for row in rows where row.ayah >= 1 && row.ayah <= count {
                    texts[row.ayah - 1] = (row.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard texts.contains(where: { !$0.isEmpty }) else {
                    throw QuranAPI.APIError.server("empty tafsir")
                }
                return texts
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

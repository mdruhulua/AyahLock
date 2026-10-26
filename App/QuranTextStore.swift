import Foundation

/// The whole Quran on the phone: Arabic (Uthmani), English (Saheeh International)
/// and Bengali (Muhiuddin Khan). Downloaded once from AlQuran Cloud, then read
/// offline from a file in the shared folder.
@MainActor
final class QuranTextStore: ObservableObject {
    static let shared = QuranTextStore()

    enum State: Equatable {
        case notDownloaded
        case downloading(step: Int, of: Int)
        case ready
        case failed(String)
    }

    struct Text: Codable {
        var arabic: [[String]]    // [surah index][ayah index]
        var english: [[String]]
        var bengali: [[String]]
        var bismillah: String     // shown above every surah except 1 and 9
    }

    struct AyahRef: Hashable, Identifiable {
        let surah: Int
        let ayah: Int
        var id: String { "\(surah):\(ayah)" }
    }

    @Published private(set) var state: State = .notDownloaded
    private(set) var text: Text?
    private var searchIndex: [(ref: AyahRef, haystack: String)] = []

    private var fileURL: URL {
        SharedStore.shared.containerURL.appendingPathComponent("QuranText.json")
    }

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(Text.self, from: data),
           Self.isComplete(saved) {
            text = saved
            state = .ready
        }
    }

    var isReady: Bool { state == .ready }

    func arabic(_ surah: Int, _ ayah: Int) -> String { line(text?.arabic, surah, ayah) }
    func english(_ surah: Int, _ ayah: Int) -> String { line(text?.english, surah, ayah) }
    func bengali(_ surah: Int, _ ayah: Int) -> String { line(text?.bengali, surah, ayah) }

    private func line(_ table: [[String]]?, _ surah: Int, _ ayah: Int) -> String {
        guard let table, surah >= 1, surah <= table.count,
              ayah >= 1, ayah <= table[surah - 1].count else { return "" }
        return table[surah - 1][ayah - 1]
    }

    /// Surah 9 has no Bismillah, and in Surah 1 it is ayah 1 itself.
    nonisolated static func showsBismillah(_ surah: Int) -> Bool { surah != 1 && surah != 9 }

    /// Ayah number counted from the start of the Quran (1–6236), as the audio service uses.
    nonisolated static func globalNumber(surah: Int, ayah: Int) -> Int {
        Surah.all.prefix(surah - 1).reduce(0) { $0 + $1.ayahCount } + ayah
    }

    // MARK: - Download

    func download() async {
        if case .downloading = state { return }
        do {
            state = .downloading(step: 1, of: 3)
            // Remove invisible byte-order marks some editions include.
            var arabic = try await Self.fetchEdition(QuranAPI.arabicEdition)
                .map { $0.map { $0.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespaces) } }
            state = .downloading(step: 2, of: 3)
            let english = try await Self.fetchEdition(QuranAPI.englishEdition)
            state = .downloading(step: 3, of: 3)
            let bengali = try await Self.fetchEdition(QuranAPI.bengaliEdition)

            // The Uthmani text puts the Bismillah at the start of ayah 1 of most
            // surahs. Show it as a heading instead, so ayah 1 is just ayah 1.
            // The marks can be written slightly differently from 1:1, so compare
            // word by word with vowel marks removed.
            let bismillah = arabic[0][0]
            let bismillahWords = bismillah.split(whereSeparator: \.isWhitespace).map { Self.fold(String($0)) }
            for index in 1..<arabic.count where Self.showsBismillah(index + 1) {
                let words = arabic[index][0].split(whereSeparator: \.isWhitespace)
                let leading = words.prefix(bismillahWords.count).map { Self.fold(String($0)) }
                if words.count > bismillahWords.count && leading == bismillahWords {
                    arabic[index][0] = words.dropFirst(bismillahWords.count).joined(separator: " ")
                }
            }

            let result = Text(arabic: arabic, english: english, bengali: bengali, bismillah: bismillah)
            guard Self.isComplete(result) else {
                throw QuranAPI.APIError.server("The download was incomplete. Please try again.")
            }
            let data = try JSONEncoder().encode(result)
            try data.write(to: fileURL, options: .atomic)
            text = result
            searchIndex = []
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private struct EditionResponse: Decodable {
        let data: Edition
        struct Edition: Decodable { let surahs: [SurahText] }
        struct SurahText: Decodable { let number: Int; let ayahs: [AyahText] }
        struct AyahText: Decodable { let text: String; let numberInSurah: Int }
    }

    nonisolated private static func fetchEdition(_ edition: String) async throws -> [[String]] {
        guard let url = URL(string: "https://api.alquran.cloud/v1/quran/\(edition)") else {
            throw QuranAPI.APIError.server("bad URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw QuranAPI.APIError.server("HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(EditionResponse.self, from: data)
        return decoded.data.surahs
            .sorted { $0.number < $1.number }
            .map { $0.ayahs.sorted { $0.numberInSurah < $1.numberInSurah }.map(\.text) }
    }

    nonisolated private static func isComplete(_ text: Text) -> Bool {
        let counts = Surah.all.map(\.ayahCount)
        return [text.arabic, text.english, text.bengali].allSatisfy { table in
            table.map(\.count) == counts && !table.joined().contains("")
        }
    }

    // MARK: - Search

    /// Finds ayahs whose English, Bengali or Arabic text contains the query.
    /// Arabic matching ignores vowel marks.
    func search(_ query: String, limit: Int = 100) -> [AyahRef] {
        let needle = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard needle.count >= 2, let text else { return [] }
        if searchIndex.isEmpty {
            for (s, surah) in text.arabic.enumerated() {
                for a in surah.indices {
                    let joined = [text.arabic[s][a], text.english[s][a], text.bengali[s][a]].joined(separator: " ")
                    searchIndex.append((AyahRef(surah: s + 1, ayah: a + 1), Self.fold(joined)))
                }
            }
        }
        var results: [AyahRef] = []
        for entry in searchIndex where entry.haystack.contains(needle) {
            results.append(entry.ref)
            if results.count >= limit { break }
        }
        return results
    }

    /// Lowercases and removes vowel marks so searches match with or without them.
    /// Arabic: removes harakat and Quranic marks, tatweel and small waw/yeh, and
    /// treats alef wasla and hamza-alefs as plain alef. Bengali is left intact.
    nonisolated static func fold(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in s.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars {
            let v = scalar.value
            if v == 0x0640 || v == 0x06E5 || v == 0x06E6 { continue }
            if scalar.properties.generalCategory == .format { continue }   // invisible marks like U+FEFF
            if scalar.properties.generalCategory == .nonspacingMark,
               (0x0300...0x036F).contains(v) || (0x0600...0x06FF).contains(v) || (0x08D0...0x08FF).contains(v) {
                continue
            }
            switch v {
            case 0x0671, 0x0622, 0x0623, 0x0625: out.append(Unicode.Scalar(0x0627)!)   // ٱ آ أ إ → ا
            case 0x0649: out.append(Unicode.Scalar(0x064A)!)                         // ى → ي
            default: out.append(scalar)
            }
        }
        return String(out)
    }

    // MARK: - Reading position

    private let lastReadKey = "lastRead"

    var lastRead: AyahRef? {
        get {
            guard let parts = UserDefaults.standard.string(forKey: lastReadKey)?.split(separator: ":"),
                  parts.count == 2, let s = Int(parts[0]), let a = Int(parts[1]) else { return nil }
            return AyahRef(surah: s, ayah: a)
        }
        set {
            UserDefaults.standard.set(newValue.map { "\($0.surah):\($0.ayah)" }, forKey: lastReadKey)
            objectWillChange.send()
        }
    }
}

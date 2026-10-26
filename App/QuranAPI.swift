import Foundation

/// Fetches Arabic text, English and Bengali translations, and per-ayah
/// recitation audio from the free AlQuran Cloud API (api.alquran.cloud),
/// then saves the audio into the shared folder so it plays offline.
enum QuranAPI {
    static let arabicEdition = "quran-uthmani"
    static let englishEdition = "en.sahih"      // Saheeh International
    static let bengaliEdition = "bn.bengali"    // Muhiuddin Khan
    static let maxRange = 20                    // keeps downloads small

    enum APIError: LocalizedError {
        case badRange
        case server(String)
        case missingAudio

        var errorDescription: String? {
            switch self {
            case .badRange: return "Choose a range of 1 to \(QuranAPI.maxRange) ayahs within the surah."
            case .server(let msg): return "The Quran server returned an error: \(msg)"
            case .missingAudio: return "No audio came back for this reciter. Try another reciter."
            }
        }
    }

    private struct Response: Decodable {
        let code: Int
        let data: [EditionAyah]
    }

    private struct EditionAyah: Decodable {
        let text: String
        let numberInSurah: Int
        let audio: String?
        let edition: Edition
    }

    private struct Edition: Decodable {
        let identifier: String
    }

    static func fetchItem(surah: Surah, from: Int, to: Int, reciterID: String, title: String) async throws -> RecitationItem {
        guard from >= 1, to >= from, to <= surah.ayahCount, to - from + 1 <= maxRange else {
            throw APIError.badRange
        }

        var arabic: [String] = []
        var english: [String] = []
        var bengali: [String] = []
        var files: [String] = []

        for ayah in from...to {
            let editions = [arabicEdition, englishEdition, bengaliEdition, reciterID].joined(separator: ",")
            guard let url = URL(string: "https://api.alquran.cloud/v1/ayah/\(surah.number):\(ayah)/editions/\(editions)") else {
                throw APIError.server("bad URL")
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw APIError.server("HTTP \(http.statusCode)")
            }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            func text(_ id: String) -> String { decoded.data.first { $0.edition.identifier == id }?.text ?? "" }

            let marker = ranged(from: from, to: to) ? " (\(ayah))" : ""
            arabic.append(text(arabicEdition) + marker)
            english.append(text(englishEdition) + marker)
            bengali.append(text(bengaliEdition) + marker)

            guard let audioString = decoded.data.first(where: { $0.edition.identifier == reciterID })?.audio else {
                throw APIError.missingAudio
            }
            let secure = audioString.replacingOccurrences(of: "http://", with: "https://")
            guard let audioURL = URL(string: secure) else { throw APIError.missingAudio }
            let fileName = audioFileName(reciterID: reciterID, surah: surah.number, ayah: ayah)
            try await download(audioURL, as: fileName)
            files.append(fileName)
        }

        let ref = from == to ? "Quran \(surah.number):\(from)" : "Quran \(surah.number):\(from)–\(to)"
        return RecitationItem(
            kind: .quran,
            title: title.isEmpty ? "\(surah.name) \(from == to ? "\(from)" : "\(from)–\(to)")" : title,
            reference: ref,
            arabic: arabic.joined(separator: " "),
            english: english.joined(separator: " "),
            bengali: bengali.joined(separator: " "),
            audioFileNames: files,
            reciterName: Reciter.name(for: reciterID))
    }

    private static func ranged(from: Int, to: Int) -> Bool { from != to }

    // MARK: - Whole-surah audio

    private struct SurahAudioResponse: Decodable {
        let data: SurahData
        struct SurahData: Decodable { let ayahs: [AyahAudio] }
        struct AyahAudio: Decodable { let numberInSurah: Int; let audio: String? }
    }

    /// Per-ayah recitation URLs for a whole surah, in ayah order (one request).
    static func audioURLs(surah: Int, reciterID: String) async throws -> [URL] {
        guard let url = URL(string: "https://api.alquran.cloud/v1/surah/\(surah)/\(reciterID)") else {
            throw APIError.server("bad URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.server("HTTP \(http.statusCode)")
        }
        let ayahs = try JSONDecoder().decode(SurahAudioResponse.self, from: data).data.ayahs
            .sorted { $0.numberInSurah < $1.numberInSurah }
        let urls = ayahs.compactMap { $0.audio.flatMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) } }
        guard urls.count == ayahs.count, !urls.isEmpty else { throw APIError.missingAudio }
        return urls
    }

    static func audioFileName(reciterID: String, surah: Int, ayah: Int) -> String {
        "\(reciterID)_\(surah)_\(ayah).mp3"
    }

    /// The saved file for this ayah and reciter, if it has been downloaded.
    static func localAudio(reciterID: String, surah: Int, ayah: Int) -> URL? {
        let url = SharedStore.shared.audioDirectory
            .appendingPathComponent(audioFileName(reciterID: reciterID, surah: surah, ayah: ayah))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Saves one ayah's audio for offline use (does nothing if already saved).
    static func saveAudio(from url: URL, reciterID: String, surah: Int, ayah: Int) async throws {
        try await download(url, as: audioFileName(reciterID: reciterID, surah: surah, ayah: ayah))
    }

    /// Builds a lock-screen item from the stored Quran text, downloading only
    /// audio that isn't saved yet, so it works offline for downloaded surahs.
    @MainActor
    static func makeItem(surah: Int, from: Int, to: Int, reciterID: String, title: String) async throws -> RecitationItem {
        let store = QuranTextStore.shared
        guard store.isReady else {
            return try await fetchItem(surah: Surah.all[surah - 1], from: from, to: to, reciterID: reciterID, title: title)
        }
        guard from >= 1, to >= from, to <= Surah.all[surah - 1].ayahCount, to - from + 1 <= maxRange else {
            throw APIError.badRange
        }
        let ayahs = Array(from...to)
        let missing = ayahs.filter { localAudio(reciterID: reciterID, surah: surah, ayah: $0) == nil }
        if !missing.isEmpty {
            let urls = try await audioURLs(surah: surah, reciterID: reciterID)
            for ayah in missing {
                try await saveAudio(from: urls[ayah - 1], reciterID: reciterID, surah: surah, ayah: ayah)
            }
        }
        let marker: (Int) -> String = { from == to ? "" : " (\($0))" }
        let name = Surah.all[surah - 1].name
        return RecitationItem(
            kind: .quran,
            title: title.isEmpty ? "\(name) \(from == to ? "\(from)" : "\(from)–\(to)")" : title,
            reference: from == to ? "Quran \(surah):\(from)" : "Quran \(surah):\(from)–\(to)",
            arabic: ayahs.map { store.arabic(surah, $0) + marker($0) }.joined(separator: " "),
            english: ayahs.map { store.english(surah, $0) + marker($0) }.joined(separator: " "),
            bengali: ayahs.map { store.bengali(surah, $0) + marker($0) }.joined(separator: " "),
            audioFileNames: ayahs.map { audioFileName(reciterID: reciterID, surah: surah, ayah: $0) },
            reciterName: Reciter.name(for: reciterID))
    }

    private static func download(_ url: URL, as fileName: String) async throws {
        let destination = SharedStore.shared.audioDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) { return }
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.server("audio HTTP \(http.statusCode)")
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }
}

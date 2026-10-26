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
            let fileName = "\(reciterID)_\(surah.number)_\(ayah).mp3"
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

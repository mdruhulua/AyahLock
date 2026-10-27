import Foundation

/// The Quran in IndoPak script, shown with the Digital Khatt IndoPak font.
///
/// The text is Tarteel's "Digital Khatt IndoPak Script – Ayah by Ayah" (QUL
/// resource 566), the encoding this font was designed for. It is read from
/// `IndoPak.json` bundled with the app, or from a copy imported on the phone.
@MainActor
final class IndoPakText: ObservableObject {
    static let shared = IndoPakText()

    /// PostScript name of the bundled font (see UIAppFonts in project.yml).
    static let fontName = "DigitalKhattIndoPakRegular"
    static let resourceName = "IndoPak"

    enum ImportError: LocalizedError {
        case unreadable
        case wrongShape(String)

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "This file isn't the IndoPak JSON. Download “Digital Khatt Indopak Script – Ayah by Ayah” as JSON from qul.tarteel.ai."
            case .wrongShape(let detail):
                return "The file doesn't contain the whole Quran (\(detail))."
            }
        }
    }

    @Published private(set) var lines: [[String]]?

    private let importedURL: URL

    init(importedURL: URL = SharedStore.shared.containerURL.appendingPathComponent("IndoPak.json"),
         bundle: Bundle = .main) {
        self.importedURL = importedURL
        let candidates = [bundle.url(forResource: Self.resourceName, withExtension: "json"), importedURL]
        for case let url? in candidates {
            if let data = try? Data(contentsOf: url), let parsed = try? Self.parse(data) {
                lines = parsed
                break
            }
        }
    }

    var isAvailable: Bool { lines != nil }

    func text(_ surah: Int, _ ayah: Int) -> String? {
        guard let lines, surah >= 1, surah <= lines.count,
              ayah >= 1, ayah <= lines[surah - 1].count else { return nil }
        return lines[surah - 1][ayah - 1]
    }

    /// The Bismillah heading: ayah 1:1 without its end-of-ayah sign and number.
    var bismillah: String? {
        guard let first = text(1, 1) else { return nil }
        // Search code points: U+06DD joins with the number after it into one
        // character, so a Character search for it alone would never match.
        let scalars = first.unicodeScalars
        let cut = scalars.firstIndex(of: "\u{06DD}") ?? scalars.endIndex
        return String(String.UnicodeScalarView(scalars[..<cut])).trimmingCharacters(in: .whitespaces)
    }

    /// Copies a downloaded QUL JSON file into the app after checking it.
    func importFile(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let parsed = try Self.parse(data)
        try data.write(to: importedURL, options: .atomic)
        lines = parsed
    }

    func removeImported() {
        try? FileManager.default.removeItem(at: importedURL)
        lines = nil
    }

    /// Accepts QUL's ayah-by-ayah JSON: an object keyed by "surah:ayah" whose values
    /// carry "text" (or are the text), or an array of objects with verse_key and text.
    nonisolated static func parse(_ data: Data) throws -> [[String]] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { throw ImportError.unreadable }

        var byKey: [String: String] = [:]
        func take(_ key: String?, _ value: Any) {
            if let s = value as? String, let key {
                byKey[key] = s
            } else if let obj = value as? [String: Any] {
                let k = (obj["verse_key"] as? String) ?? key
                if let k, let t = obj["text"] as? String { byKey[k] = t }
            }
        }
        if let dict = json as? [String: Any] {
            for (k, v) in dict { take(k, v) }
        } else if let array = json as? [Any] {
            for v in array { take(nil, v) }
        } else {
            throw ImportError.unreadable
        }

        var result: [[String]] = []
        for surah in Surah.all {
            var ayahs: [String] = []
            for ayah in 1...surah.ayahCount {
                guard let text = byKey["\(surah.number):\(ayah)"], !text.isEmpty else {
                    if byKey.isEmpty { throw ImportError.unreadable }
                    throw ImportError.wrongShape("ayah \(surah.number):\(ayah) is missing")
                }
                ayahs.append(text.replacingOccurrences(of: "\u{FEFF}", with: ""))
            }
            result.append(ayahs)
        }
        return result
    }
}

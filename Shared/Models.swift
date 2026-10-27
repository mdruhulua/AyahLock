import Foundation

/// Where an item's text and audio came from.
enum ItemKind: String, Codable {
    case quran      // fetched from the Quran API (one ayah or a short range)
    case customDua  // typed in by you, with an audio file you imported
}

/// One thing you can pin to the lock screen and recite on repeat.
struct RecitationItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var kind: ItemKind
    var title: String
    var reference: String          // e.g. "Quran 2:255" or the dua's source
    var arabic: String
    var english: String
    var bengali: String
    var audioFileNames: [String]   // files in SharedStore.audioDirectory, played in order
    var reciterName: String
}

/// Which Arabic script the reader shows.
enum QuranScript: String, Codable, CaseIterable, Identifiable {
    case uthmani   // Madinah style
    case indopak   // South Asian style (needs the IndoPak text file)
    var id: String { rawValue }
    var label: String { self == .uthmani ? "Uthmani (Madinah)" : "IndoPak" }
}

/// Your playback and display choices. Shared with the widget.
struct PlaybackSettings: Codable, Equatable {
    var repeatCount: Int = 7          // 0 means "until I stop it"
    var gapSeconds: Double = 1        // pause between repeats
    var showEnglish: Bool = true
    var showBengali: Bool = true
    var maxMinutes: Int = 30          // safety cap so a forgotten loop stops
    var defaultReciterID: String = Reciter.all[0].id
    var arabicFontSize: Double = 26   // Quran reader text size
    var script: QuranScript = .uthmani
    var tafsirSlug: String = "en-tafisr-ibn-kathir"

    enum CodingKeys: String, CodingKey {
        case repeatCount, gapSeconds, showEnglish, showBengali, maxMinutes
        case defaultReciterID, arabicFontSize, script, tafsirSlug
    }
}

extension PlaybackSettings {
    /// Reads saved settings, keeping defaults for anything added in a later version,
    /// so an app update never wipes your choices.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        repeatCount = try c.decodeIfPresent(Int.self, forKey: .repeatCount) ?? repeatCount
        gapSeconds = try c.decodeIfPresent(Double.self, forKey: .gapSeconds) ?? gapSeconds
        showEnglish = try c.decodeIfPresent(Bool.self, forKey: .showEnglish) ?? showEnglish
        showBengali = try c.decodeIfPresent(Bool.self, forKey: .showBengali) ?? showBengali
        maxMinutes = try c.decodeIfPresent(Int.self, forKey: .maxMinutes) ?? maxMinutes
        defaultReciterID = try c.decodeIfPresent(String.self, forKey: .defaultReciterID) ?? defaultReciterID
        arabicFontSize = try c.decodeIfPresent(Double.self, forKey: .arabicFontSize) ?? arabicFontSize
        script = (try? c.decodeIfPresent(QuranScript.self, forKey: .script)) ?? script
        tafsirSlug = try c.decodeIfPresent(String.self, forKey: .tafsirSlug) ?? tafsirSlug
    }
}

struct Reciter: Identifiable, Hashable {
    let id: String     // alquran.cloud audio edition identifier
    let name: String

    static let all: [Reciter] = [
        Reciter(id: "ar.alafasy", name: "Mishary Alafasy"),
        Reciter(id: "ar.husary", name: "Mahmoud Khalil Al-Husary"),
        Reciter(id: "ar.minshawi", name: "Mohamed Siddiq Al-Minshawi"),
        Reciter(id: "ar.abdulbasitmurattal", name: "Abdul Basit (Murattal)"),
        Reciter(id: "ar.mahermuaiqly", name: "Maher Al-Muaiqly"),
        Reciter(id: "ar.abdurrahmaansudais", name: "Abdurrahmaan As-Sudais"),
    ]

    static func name(for id: String) -> String {
        all.first { $0.id == id }?.name ?? id
    }
}

struct Surah: Identifiable, Hashable {
    let number: Int
    let name: String
    let ayahCount: Int
    var id: Int { number }

    static let all: [Surah] = {
        let names = [
            "Al-Fatihah", "Al-Baqarah", "Aal-Imran", "An-Nisa", "Al-Ma'idah", "Al-An'am", "Al-A'raf", "Al-Anfal",
            "At-Tawbah", "Yunus", "Hud", "Yusuf", "Ar-Ra'd", "Ibrahim", "Al-Hijr", "An-Nahl", "Al-Isra", "Al-Kahf",
            "Maryam", "Taha", "Al-Anbiya", "Al-Hajj", "Al-Mu'minun", "An-Nur", "Al-Furqan", "Ash-Shu'ara",
            "An-Naml", "Al-Qasas", "Al-Ankabut", "Ar-Rum", "Luqman", "As-Sajdah", "Al-Ahzab", "Saba", "Fatir",
            "Ya-Sin", "As-Saffat", "Sad", "Az-Zumar", "Ghafir", "Fussilat", "Ash-Shura", "Az-Zukhruf",
            "Ad-Dukhan", "Al-Jathiyah", "Al-Ahqaf", "Muhammad", "Al-Fath", "Al-Hujurat", "Qaf", "Adh-Dhariyat",
            "At-Tur", "An-Najm", "Al-Qamar", "Ar-Rahman", "Al-Waqi'ah", "Al-Hadid", "Al-Mujadilah", "Al-Hashr",
            "Al-Mumtahanah", "As-Saff", "Al-Jumu'ah", "Al-Munafiqun", "At-Taghabun", "At-Talaq", "At-Tahrim",
            "Al-Mulk", "Al-Qalam", "Al-Haqqah", "Al-Ma'arij", "Nuh", "Al-Jinn", "Al-Muzzammil", "Al-Muddaththir",
            "Al-Qiyamah", "Al-Insan", "Al-Mursalat", "An-Naba", "An-Nazi'at", "Abasa", "At-Takwir", "Al-Infitar",
            "Al-Mutaffifin", "Al-Inshiqaq", "Al-Buruj", "At-Tariq", "Al-A'la", "Al-Ghashiyah", "Al-Fajr",
            "Al-Balad", "Ash-Shams", "Al-Layl", "Ad-Duha", "Ash-Sharh", "At-Tin", "Al-Alaq", "Al-Qadr",
            "Al-Bayyinah", "Az-Zalzalah", "Al-Adiyat", "Al-Qari'ah", "At-Takathur", "Al-Asr", "Al-Humazah",
            "Al-Fil", "Quraysh", "Al-Ma'un", "Al-Kawthar", "Al-Kafirun", "An-Nasr", "Al-Masad", "Al-Ikhlas",
            "Al-Falaq", "An-Nas",
        ]
        let counts = [
            7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128, 111, 110, 98, 135, 112, 78,
            118, 64, 77, 227, 93, 88, 69, 60, 34, 30, 73, 54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38,
            29, 18, 45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12, 30, 52, 52, 44, 28, 28, 20,
            56, 40, 31, 50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19, 26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11,
            11, 8, 3, 9, 5, 4, 7, 3, 6, 3, 5, 4, 5, 6,
        ]
        return zip(names, counts).enumerated().map { Surah(number: $0.offset + 1, name: $0.element.0, ayahCount: $0.element.1) }
    }()
}

/// Well-known passages and Quranic duas, by reference.
/// Where a dua is only part of an ayah, the whole ayah is played.
struct QuranPreset: Identifiable, Hashable {
    let title: String
    let surah: Int
    let from: Int
    let to: Int
    var id: String { "\(surah):\(from)-\(to)" }

    static let all: [QuranPreset] = [
        QuranPreset(title: "Ayat al-Kursi", surah: 2, from: 255, to: 255),
        QuranPreset(title: "Last two ayahs of Al-Baqarah", surah: 2, from: 285, to: 286),
        QuranPreset(title: "Al-Fatihah", surah: 1, from: 1, to: 7),
        QuranPreset(title: "Al-Ikhlas", surah: 112, from: 1, to: 4),
        QuranPreset(title: "Al-Falaq", surah: 113, from: 1, to: 5),
        QuranPreset(title: "An-Nas", surah: 114, from: 1, to: 6),
        QuranPreset(title: "Rabbana atina fid-dunya hasanah", surah: 2, from: 201, to: 201),
        QuranPreset(title: "Rabbana la tuzigh qulubana", surah: 3, from: 8, to: 8),
        QuranPreset(title: "Hasbunallahu wa ni'mal wakil", surah: 3, from: 173, to: 173),
        QuranPreset(title: "Rabbana zalamna anfusana", surah: 7, from: 23, to: 23),
        QuranPreset(title: "Rabbij'alni muqimas-salah", surah: 14, from: 40, to: 41),
        QuranPreset(title: "Rabbir-hamhuma (for parents)", surah: 17, from: 24, to: 24),
        QuranPreset(title: "Rabbi zidni 'ilma", surah: 20, from: 114, to: 114),
        QuranPreset(title: "Dua of Yunus", surah: 21, from: 87, to: 87),
        QuranPreset(title: "Rabbana hab lana min azwajina", surah: 25, from: 74, to: 74),
        QuranPreset(title: "Rabbi inni lima anzalta", surah: 28, from: 24, to: 24),
    ]
}

extension String {
    /// Shortens long text for places with strict size limits (Live Activities).
    func clipped(_ max: Int) -> String {
        count <= max ? self : String(prefix(max)) + "…"
    }
}

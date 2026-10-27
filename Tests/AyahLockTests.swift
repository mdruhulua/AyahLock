import AVFoundation
import CoreText
import UIKit
import XCTest
@testable import AyahLock

/// Checks the built-in Quran data (no network needed).
final class QuranDataTests: XCTestCase {
    func testSurahListIsComplete() {
        XCTAssertEqual(Surah.all.count, 114)
        XCTAssertEqual(Surah.all.reduce(0) { $0 + $1.ayahCount }, 6236)
        XCTAssertEqual(Surah.all[1].name, "Al-Baqarah")
        XCTAssertEqual(Surah.all[1].ayahCount, 286)
        XCTAssertEqual(Surah.all[113].name, "An-Nas")
    }

    func testPresetsPointToRealAyahs() {
        for preset in QuranPreset.all {
            let surah = Surah.all[preset.surah - 1]
            XCTAssertGreaterThanOrEqual(preset.from, 1, preset.title)
            XCTAssertLessThanOrEqual(preset.from, preset.to, preset.title)
            XCTAssertLessThanOrEqual(preset.to, surah.ayahCount, preset.title)
            XCTAssertLessThanOrEqual(preset.to - preset.from + 1, QuranAPI.maxRange, preset.title)
        }
    }

    func testSilenceFileIsPlayable() throws {
        let url = try XCTUnwrap(Silence.url(seconds: 2))
        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertEqual(player.duration, 2, accuracy: 0.05)
    }
}

/// Downloads real content from AlQuran Cloud, exactly as the app does.
final class QuranDownloadTests: XCTestCase {
    private func containsArabic(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
    }

    private func containsBengali(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x0980...0x09FF).contains($0.value) }
    }

    func testAyatAlKursiDownloadsTextTranslationsAndAudio() async throws {
        let item = try await QuranAPI.fetchItem(
            surah: Surah.all[1], from: 255, to: 255, reciterID: "ar.alafasy", title: "Ayat al-Kursi")

        XCTAssertEqual(item.title, "Ayat al-Kursi")
        XCTAssertEqual(item.reference, "Quran 2:255")
        XCTAssertTrue(containsArabic(item.arabic), "Arabic text missing: \(item.arabic.prefix(60))")
        XCTAssertTrue(item.english.contains("Allah"), "English text looks wrong: \(item.english.prefix(80))")
        XCTAssertTrue(containsBengali(item.bengali), "Bengali text missing: \(item.bengali.prefix(60))")
        XCTAssertEqual(item.audioFileNames.count, 1)

        let url = SharedStore.shared.audioDirectory.appendingPathComponent(item.audioFileNames[0])
        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertGreaterThan(player.duration, 20, "Ayat al-Kursi audio is unexpectedly short")
    }

    func testRangeDownloadsOneAudioFilePerAyah() async throws {
        let item = try await QuranAPI.fetchItem(
            surah: Surah.all[111], from: 1, to: 4, reciterID: "ar.alafasy", title: "")
        XCTAssertEqual(item.title, "Al-Ikhlas 1–4")
        XCTAssertEqual(item.audioFileNames.count, 4)
        XCTAssertTrue(item.english.contains("(4)"), "Ayah numbers missing in a range")
    }

    func testEveryReciterHasAudio() async throws {
        var failures: [String] = []
        for reciter in Reciter.all {
            do {
                let item = try await QuranAPI.fetchItem(
                    surah: Surah.all[0], from: 1, to: 1, reciterID: reciter.id, title: "")
                let url = SharedStore.shared.audioDirectory.appendingPathComponent(item.audioFileNames[0])
                let player = try AVAudioPlayer(contentsOf: url)
                if player.duration < 1 { failures.append("\(reciter.id): audio too short") }
            } catch {
                failures.append("\(reciter.id): \(error.localizedDescription)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "Reciters with problems: \(failures.joined(separator: "; "))")
    }

    func testRejectsTooLongRange() async {
        do {
            _ = try await QuranAPI.fetchItem(
                surah: Surah.all[1], from: 1, to: 50, reciterID: "ar.alafasy", title: "")
            XCTFail("A 50-ayah range should be refused")
        } catch {
            // expected
        }
    }
}

/// Checks the repeat player with short generated audio, so it runs quickly.
@MainActor
final class RepeatPlayerTests: XCTestCase {
    private var savedSettings = PlaybackSettings()

    override func setUp() async throws {
        savedSettings = SharedStore.shared.settings
    }

    override func tearDown() async throws {
        RecitationPlayer.shared.stop()
        SharedStore.shared.settings = savedSettings
    }

    /// An item whose "recitation" is a short silent clip.
    private func makeTestItem(seconds: Double = 0.4) throws -> RecitationItem {
        let source = try XCTUnwrap(Silence.url(seconds: seconds))
        let name = "test_clip_\(UUID().uuidString).wav"
        try FileManager.default.copyItem(
            at: source, to: SharedStore.shared.audioDirectory.appendingPathComponent(name))
        return RecitationItem(
            kind: .customDua, title: "Test", reference: "Test", arabic: "بِسْمِ ٱللَّهِ",
            english: "In the name of Allah", bengali: "আল্লাহর নামে",
            audioFileNames: [name], reciterName: "Test")
    }

    private func waitUntilStopped(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while RecitationPlayer.shared.isActive && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func testRepeatsExactlyTheChosenNumberOfTimesThenStops() async throws {
        SharedStore.shared.settings = PlaybackSettings(repeatCount: 3, gapSeconds: 0)
        let player = RecitationPlayer.shared
        player.play(try makeTestItem())

        XCTAssertTrue(player.isActive, "Playback didn't start: \(player.lastError ?? "no error message")")
        await waitUntilStopped(timeout: 15)

        XCTAssertNil(player.lastError)
        XCTAssertFalse(player.isActive, "Player was still running after 3 repeats")
        XCTAssertEqual(player.completedRepeats, 3)
    }

    func testGapBetweenRepeatsIsAdded() async throws {
        SharedStore.shared.settings = PlaybackSettings(repeatCount: 2, gapSeconds: 1)
        let player = RecitationPlayer.shared
        let started = Date()
        player.play(try makeTestItem(seconds: 0.3))
        await waitUntilStopped(timeout: 15)

        XCTAssertEqual(player.completedRepeats, 2)
        // 2 × (0.3 s clip + 1 s gap) ≈ 2.6 s
        XCTAssertGreaterThan(Date().timeIntervalSince(started), 2.2)
    }

    func testUntilStoppedKeepsGoingAndStopWorks() async throws {
        SharedStore.shared.settings = PlaybackSettings(repeatCount: 0, gapSeconds: 0)
        let player = RecitationPlayer.shared
        player.play(try makeTestItem(seconds: 0.2))

        try await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertTrue(player.isActive, "\"Until I stop it\" ended by itself")
        XCTAssertGreaterThanOrEqual(player.completedRepeats, 3)

        player.stop()
        XCTAssertFalse(player.isActive)
    }

    func testPauseAndResume() async throws {
        SharedStore.shared.settings = PlaybackSettings(repeatCount: 50, gapSeconds: 0)
        let player = RecitationPlayer.shared
        player.play(try makeTestItem(seconds: 0.3))

        player.pause()
        XCTAssertTrue(player.isPaused)
        let countWhilePaused = player.completedRepeats
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(player.completedRepeats, countWhilePaused, "Repeats continued while paused")

        player.resume()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertGreaterThan(player.completedRepeats, countWhilePaused, "Resume didn't continue")
    }

    func testMissingAudioFileShowsAnError() async throws {
        let item = RecitationItem(
            kind: .customDua, title: "Broken", reference: "Test", arabic: "x", english: "", bengali: "",
            audioFileNames: ["does_not_exist.mp3"], reciterName: "Test")
        RecitationPlayer.shared.play(item)
        XCTAssertFalse(RecitationPlayer.shared.isActive)
        XCTAssertNotNil(RecitationPlayer.shared.lastError)
    }
}

/// Checks saving, pinning and cleanup.
@MainActor
final class LibraryTests: XCTestCase {
    func testAddPinsAndDeleteRemovesUnusedAudio() throws {
        let library = LibraryModel()
        let name = "test_lib_\(UUID().uuidString).wav"
        let fileURL = SharedStore.shared.audioDirectory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: XCTUnwrap(Silence.url(seconds: 0.2)), to: fileURL)

        let item = RecitationItem(
            kind: .customDua, title: "Library test", reference: "Test", arabic: "x", english: "", bengali: "",
            audioFileNames: [name], reciterName: "Test")
        library.add(item)

        XCTAssertEqual(library.pinnedID, item.id)
        XCTAssertEqual(SharedStore.shared.pinned?.id, item.id, "Widget storage didn't receive the pinned item")

        library.delete(at: IndexSet(integer: 0))
        XCTAssertFalse(library.items.contains { $0.id == item.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "Audio file wasn't cleaned up")
    }
}

/// The whole-Quran text: download, completeness, Bismillah handling, search.
@MainActor
final class QuranTextTests: XCTestCase {
    override func setUp() async throws {
        let store = QuranTextStore.shared
        if !store.isReady { await store.download() }
        if case .failed(let message) = store.state { XCTFail("Download failed: \(message)") }
    }

    func testWholeQuranIsStoredInAllThreeLanguages() throws {
        let store = QuranTextStore.shared
        XCTAssertTrue(store.isReady)
        let text = try XCTUnwrap(store.text)
        XCTAssertEqual(text.arabic.joined().count, 6236)
        XCTAssertEqual(text.english.joined().count, 6236)
        XCTAssertEqual(text.bengali.joined().count, 6236)
        XCTAssertTrue(store.english(112, 1).contains("Allah"), store.english(112, 1))
        XCTAssertTrue(store.bengali(2, 255).unicodeScalars.contains { (0x0980...0x09FF).contains($0.value) })
        XCTAssertFalse(store.arabic(114, 6).isEmpty)
    }

    func testBismillahIsAHeadingNotPartOfAyahOne() {
        let store = QuranTextStore.shared
        let bismillah = store.text?.bismillah ?? ""
        XCTAssertFalse(bismillah.isEmpty)
        XCTAssertEqual(store.arabic(1, 1), bismillah, "In Al-Fatihah the Bismillah is ayah 1")
        XCTAssertFalse(store.arabic(2, 1).contains(bismillah))
        func codes(_ t: String) -> String {
            t.unicodeScalars.prefix(40).map { String(format: "%04X", $0.value) }.joined(separator: " ")
        }
        XCTAssertLessThan(store.arabic(2, 1).count, 15,
            "2:1 should be just Alif-Lam-Mim: \(store.arabic(2, 1)) | 1:1 codes: \(codes(store.arabic(1, 1))) | 2:1 codes: \(codes(store.arabic(2, 1)))")
        XCTAssertFalse(store.arabic(9, 1).hasPrefix(bismillah), "Surah 9 has no Bismillah")
        XCTAssertFalse(QuranTextStore.showsBismillah(9))
        XCTAssertTrue(QuranTextStore.showsBismillah(36))
    }

    func testTextIsSavedForOfflineUse() {
        let reloaded = QuranTextStore()
        XCTAssertTrue(reloaded.isReady, "A fresh launch should read the saved text without downloading")
        XCTAssertEqual(reloaded.arabic(36, 1), QuranTextStore.shared.arabic(36, 1))
    }

    func testSearchFindsEnglishAndArabicWithoutVowelMarks() {
        let store = QuranTextStore.shared
        XCTAssertTrue(store.search("Kursi").contains(AyahRef(surah: 2, ayah: 255)), "English search failed")
        XCTAssertTrue(store.search("الرحمن").contains(AyahRef(surah: 55, ayah: 1)), "Arabic search failed")
        XCTAssertTrue(store.search("x").isEmpty, "One letter should not search")
    }

    func testGlobalAyahNumbers() {
        XCTAssertEqual(QuranTextStore.globalNumber(surah: 1, ayah: 1), 1)
        XCTAssertEqual(QuranTextStore.globalNumber(surah: 2, ayah: 255), 262)
        XCTAssertEqual(QuranTextStore.globalNumber(surah: 114, ayah: 6), 6236)
    }

    func testPinningFromReaderUsesStoredText() async throws {
        let item = try await QuranAPI.makeItem(surah: 36, from: 58, to: 58, reciterID: "ar.alafasy", title: "")
        XCTAssertEqual(item.title, "Ya-Sin 58")
        XCTAssertEqual(item.arabic, QuranTextStore.shared.arabic(36, 58))
        XCTAssertEqual(item.bengali, QuranTextStore.shared.bengali(36, 58))
        XCTAssertNotNil(QuranAPI.localAudio(reciterID: "ar.alafasy", surah: 36, ayah: 58))
    }
}

/// Surah playback order, offline saving, and real streaming playback.
@MainActor
final class SurahPlayerTests: XCTestCase {
    override func tearDown() async throws {
        SurahAudioPlayer.shared.stop()
    }

    func testPlaylistOrder() async throws {
        let player = SurahAudioPlayer.shared
        let ikhlas = try await player.playlist(surah: 112, from: 1, reciterID: "ar.alafasy")
        XCTAssertEqual(ikhlas.map(\.ayah), [0, 1, 2, 3, 4], "Bismillah then ayahs 1–4")

        let tawbah = try await player.playlist(surah: 9, from: 1, reciterID: "ar.alafasy")
        XCTAssertEqual(tawbah.first?.ayah, 1, "Surah 9 starts without Bismillah")
        XCTAssertEqual(tawbah.count, 129)

        let fromMiddle = try await player.playlist(surah: 2, from: 255, reciterID: "ar.alafasy")
        XCTAssertEqual(fromMiddle.first?.ayah, 255)
        XCTAssertEqual(fromMiddle.count, 32)

        let fatihah = try await player.playlist(surah: 1, from: 1, reciterID: "ar.alafasy")
        XCTAssertEqual(fatihah.map(\.ayah), Array(1...7), "No extra Bismillah in Al-Fatihah")
    }

    func testSaveSurahForOffline() async throws {
        let player = SurahAudioPlayer.shared
        player.startDownload(surah: 108, reciterID: "ar.alafasy")
        let deadline = Date().addingTimeInterval(60)
        while player.download != nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTAssertNil(player.lastError)
        XCTAssertTrue(player.isDownloaded(surah: 108, reciterID: "ar.alafasy"))

        let playlist = try await player.playlist(surah: 108, from: 1, reciterID: "ar.alafasy")
        XCTAssertTrue(playlist.filter { $0.ayah > 0 }.allSatisfy(\.url.isFileURL), "Saved surah should play from the phone")

        player.deleteDownload(surah: 108, reciterID: "ar.alafasy", keeping: [])
        XCTAssertFalse(player.isDownloaded(surah: 108, reciterID: "ar.alafasy"))
    }

    func testStreamingPlaybackAdvancesThroughAyahs() async throws {
        let player = SurahAudioPlayer.shared
        await player.play(surah: 112, from: 1, reciterID: "ar.alafasy")
        XCTAssertNil(player.lastError)
        XCTAssertTrue(player.hasSession)

        let deadline = Date().addingTimeInterval(45)
        while (player.currentAyah ?? 0) < 2 && player.hasSession && Date() < deadline {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        XCTAssertGreaterThanOrEqual(player.currentAyah ?? 0, 2, "Playback didn't move past ayah 1")
    }

    func testStartingOnePlayerStopsTheOther() async throws {
        await SurahAudioPlayer.shared.play(surah: 112, from: 1, reciterID: "ar.alafasy")
        XCTAssertTrue(SurahAudioPlayer.shared.hasSession)

        let source = try XCTUnwrap(Silence.url(seconds: 0.5))
        let name = "test_switch_\(UUID().uuidString).wav"
        try FileManager.default.copyItem(at: source, to: SharedStore.shared.audioDirectory.appendingPathComponent(name))
        RecitationPlayer.shared.play(RecitationItem(
            kind: .customDua, title: "t", reference: "t", arabic: "x", english: "", bengali: "",
            audioFileNames: [name], reciterName: "t"))

        XCTAssertFalse(SurahAudioPlayer.shared.hasSession, "Surah playback should stop when a pinned item plays")
        RecitationPlayer.shared.stop()
    }
}

/// Settings saved by an older version must survive an update.
final class SettingsMigrationTests: XCTestCase {
    func testOlderSavedSettingsKeepTheirValues() throws {
        let old = #"{"repeatCount":5,"gapSeconds":3,"showEnglish":false,"showBengali":true,"maxMinutes":60,"defaultReciterID":"ar.husary"}"#
        let s = try JSONDecoder().decode(PlaybackSettings.self, from: Data(old.utf8))
        XCTAssertEqual(s.repeatCount, 5)
        XCTAssertEqual(s.gapSeconds, 3)
        XCTAssertFalse(s.showEnglish)
        XCTAssertEqual(s.defaultReciterID, "ar.husary")
        XCTAssertEqual(s.script, .uthmani, "New settings get their defaults")
        XCTAssertEqual(s.tafsirSlug, "en-tafisr-ibn-kathir")
        XCTAssertEqual(s.arabicFontSize, 26)
    }

    func testRoundTrip() throws {
        var s = PlaybackSettings()
        s.script = .indopak
        s.tafsirSlug = "bn-tafsir-ahsanul-bayaan"
        let back = try JSONDecoder().decode(PlaybackSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }
}

/// Tafsir downloads, grouping and offline storage (real data).
@MainActor
final class TafsirTests: XCTestCase {
    private func tempStore() -> TafsirStore {
        TafsirStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("tafsir-test-\(UUID().uuidString)", isDirectory: true))
    }

    func testEveryTafsirLoadsInItsLanguage() async throws {
        let store = tempStore()
        for source in TafsirSource.all {
            let texts = try await store.surahTexts(slug: source.slug, surah: 112)
            XCTAssertEqual(texts.count, 4, source.slug)
            XCTAssertTrue(texts.allSatisfy { !$0.isEmpty }, "\(source.slug) has empty ayahs")
            let bengali = texts.joined().unicodeScalars.contains { (0x0980...0x09FF).contains($0.value) }
            XCTAssertEqual(bengali, source.language == "Bengali", "\(source.slug) is in the wrong language")
        }
    }

    func testAyatAlKursiTafsir() async throws {
        let store = tempStore()
        let en = try await store.entry(slug: "en-tafisr-ibn-kathir", surah: 2, ayah: 255)
        XCTAssertTrue(en.text.contains("Allah"), String(en.text.prefix(100)))
        XCTAssertLessThanOrEqual(en.fromAyah, 255)
        XCTAssertGreaterThanOrEqual(en.toAyah, 255)
        let bn = try await store.entry(slug: "bn-tafsir-ahsanul-bayaan", surah: 2, ayah: 255)
        XCTAssertTrue(bn.text.unicodeScalars.contains { (0x0980...0x09FF).contains($0.value) })
    }

    func testSavedForOfflineAfterFirstOpen() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tafsir-offline-\(UUID().uuidString)")
        let first = TafsirStore(directory: dir)
        XCTAssertFalse(first.isSaved(slug: "bn-tafsir-abu-bakr-zakaria", surah: 1))
        let online = try await first.surahTexts(slug: "bn-tafsir-abu-bakr-zakaria", surah: 1)
        XCTAssertTrue(first.isSaved(slug: "bn-tafsir-abu-bakr-zakaria", surah: 1))
        XCTAssertEqual(first.savedSurahCount(slug: "bn-tafsir-abu-bakr-zakaria"), 1)

        let reopened = TafsirStore(directory: dir)
        let fromDisk = try await reopened.surahTexts(slug: "bn-tafsir-abu-bakr-zakaria", surah: 1)
        XCTAssertEqual(fromDisk, online)

        reopened.deleteAll(slug: "bn-tafsir-abu-bakr-zakaria")
        XCTAssertFalse(reopened.isSaved(slug: "bn-tafsir-abu-bakr-zakaria", surah: 1))
    }

    func testGroupingOfSharedExplanations() {
        let texts = ["a", "b", "b", "b", "c", ""]
        XCTAssertEqual(TafsirStore.group(texts, ayah: 1), TafsirEntry(text: "a", fromAyah: 1, toAyah: 1))
        XCTAssertEqual(TafsirStore.group(texts, ayah: 3), TafsirEntry(text: "b", fromAyah: 2, toAyah: 4))
        XCTAssertEqual(TafsirStore.group(texts, ayah: 6), TafsirEntry(text: "", fromAyah: 6, toAyah: 6))
    }
}

/// Bookmarks with notes: add, edit, persist, delete, export.
@MainActor
final class BookmarkTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() async throws {
        fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarks-\(UUID().uuidString).json")
    }

    func testAddEditPersistDelete() {
        let store = BookmarkStore(fileURL: fileURL)
        XCTAssertFalse(store.isBookmarked(surah: 2, ayah: 255))

        store.save(surah: 2, ayah: 255, note: "  Recite after every salah  ")
        store.save(surah: 1, ayah: 1, note: "")
        XCTAssertEqual(store.bookmark(surah: 2, ayah: 255)?.note, "Recite after every salah", "Note should be trimmed")

        store.save(surah: 2, ayah: 255, note: "Before sleeping too")
        XCTAssertEqual(store.bookmarks.count, 2, "Editing must not create a duplicate")

        let reopened = BookmarkStore(fileURL: fileURL)
        XCTAssertEqual(reopened.bookmark(surah: 2, ayah: 255)?.note, "Before sleeping too", "Bookmarks didn't persist")
        XCTAssertEqual(reopened.sorted(.quran).map(\.ayah), [1, 255])
        XCTAssertEqual(reopened.sorted(.recent).first?.ayah, 255)

        reopened.delete(surah: 1, ayah: 1)
        XCTAssertEqual(BookmarkStore(fileURL: fileURL).bookmarks.count, 1)
    }

    func testSearchAndExport() {
        let store = BookmarkStore(fileURL: fileURL)
        store.save(surah: 2, ayah: 255, note: "Protection at night")
        store.save(surah: 112, ayah: 1, note: "Equal to a third")
        XCTAssertEqual(store.filtered("protection", order: .quran).map(\.surah), [2])
        XCTAssertEqual(store.filtered("Ikhlas", order: .quran).map(\.surah), [112], "Search by surah name")

        let text = store.exportText(store: QuranTextStore.shared)
        XCTAssertTrue(text.contains("Al-Baqarah 2:255"))
        XCTAssertTrue(text.contains("Note: Protection at night"))
    }
}

/// The IndoPak font and text loader.
@MainActor
final class IndoPakTests: XCTestCase {
    /// Ayahs in the Digital Khatt IndoPak encoding (2:1, 73:4, 112:1), written as code points.
    static let samples = [
        "\u{0627}\u{0644}\u{089C}\u{0645}\u{0651}\u{089C} \u{06DD}\u{0661}\u{06DA}",
        "\u{0627}\u{064E}\u{0648}\u{0652} \u{0632}\u{0650}\u{062F}\u{0652} \u{0639}\u{064E}\u{0644}\u{064E}\u{064A}\u{0652}\u{0647}\u{0650} \u{0648}\u{064E}\u{0631}\u{064E}\u{062A}\u{0651}\u{0650}\u{0644}\u{0650} \u{0627}\u{0644}\u{0652}\u{0642}\u{064F}\u{0631}\u{0652}\u{0627}\u{0670}\u{0646}\u{064E} \u{062A}\u{064E}\u{0631}\u{0652}\u{062A}\u{0650}\u{064A}\u{0652}\u{0644}\u{064B}\u{0627} \u{06DD}\u{0664}\u{0615}",
        "\u{0642}\u{064F}\u{0644}\u{0652} \u{0647}\u{064F}\u{0648}\u{064E} \u{0627}\u{0644}\u{0644}\u{0651}\u{0670}\u{0647}\u{064F} \u{0627}\u{064E}\u{062D}\u{064E}\u{062F}\u{064C} \u{06DD}\u{0661}\u{06DA}",
    ]

    func testFontIsInstalledAndCoversTheText() throws {
        let font = try XCTUnwrap(UIFont(name: IndoPakText.fontName, size: 24), "IndoPak font isn't registered")
        let ctFont = font as CTFont
        for sample in Self.samples {
            for scalar in Set(sample.unicodeScalars) where scalar != " " {
                var units = Array(String(scalar).utf16)
                var glyphs = Array(repeating: CGGlyph(0), count: units.count)
                let ok = CTFontGetGlyphsForCharacters(ctFont, &units, &glyphs, units.count)
                XCTAssertTrue(ok && glyphs.allSatisfy { $0 != 0 },
                              String(format: "Font has no glyph for U+%04X", scalar.value))
            }
        }
    }

    func testLicenceShipsWithTheApp() {
        XCTAssertNotNil(Bundle.main.url(forResource: "DigitalKhattIndoPak-OFL", withExtension: "txt"))
    }

    private func fullQuranJSON(missing: String? = nil, asArray: Bool = false) throws -> Data {
        var dict: [String: Any] = [:]
        var array: [[String: Any]] = []
        for surah in Surah.all {
            for ayah in 1...surah.ayahCount {
                let key = "\(surah.number):\(ayah)"
                if key == missing { continue }
                let text = key == "1:1" ? "بسم \u{06DD}\u{0661}" : "text \(key)"
                dict[key] = ["verse_key": key, "text": text, "script_type": "text_digital_khatt_indopak"]
                array.append(["verse_key": key, "text": text])
            }
        }
        return try JSONSerialization.data(withJSONObject: asArray ? array : dict)
    }

    func testParsesQULFormatsAndRejectsIncompleteFiles() throws {
        let parsed = try IndoPakText.parse(fullQuranJSON())
        XCTAssertEqual(parsed.joined().count, 6236)
        XCTAssertEqual(parsed[1][254], "text 2:255")
        XCTAssertEqual(try IndoPakText.parse(fullQuranJSON(asArray: true))[113][5], "text 114:6")
        XCTAssertThrowsError(try IndoPakText.parse(fullQuranJSON(missing: "36:10")))
        XCTAssertThrowsError(try IndoPakText.parse(Data("not json".utf8)))
    }

    func testImportMakesTheScriptAvailable() throws {
        let importedURL = FileManager.default.temporaryDirectory.appendingPathComponent("indopak-\(UUID().uuidString).json")
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("download-\(UUID().uuidString).json")
        try fullQuranJSON().write(to: source)

        let store = IndoPakText(importedURL: importedURL, bundle: Bundle(for: Self.self))
        XCTAssertFalse(store.isAvailable)
        try store.importFile(from: source)
        XCTAssertTrue(store.isAvailable)
        XCTAssertEqual(store.text(2, 255), "text 2:255")
        XCTAssertEqual(store.bismillah, "بسم", "Bismillah heading should drop the end-of-ayah sign")

        XCTAssertTrue(IndoPakText(importedURL: importedURL, bundle: Bundle(for: Self.self)).isAvailable, "Import didn't persist")
        store.removeImported()
        XCTAssertFalse(store.isAvailable)
    }

    func testBundledTextIfPresent() throws {
        let store = IndoPakText.shared
        guard store.isAvailable else {
            throw XCTSkip("IndoPak.json isn't bundled yet")
        }
        XCTAssertEqual(store.lines?.joined().count, 6236)
        let font = try XCTUnwrap(UIFont(name: IndoPakText.fontName, size: 24)) as CTFont
        var missing = Set<UInt32>()
        for scalar in Set(store.lines!.joined().joined().unicodeScalars) where scalar != " " {
            var units = Array(String(scalar).utf16)
            var glyphs = Array(repeating: CGGlyph(0), count: units.count)
            if !CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count) || glyphs.contains(0) {
                missing.insert(scalar.value)
            }
        }
        XCTAssertTrue(missing.isEmpty, "Characters the font can't draw: \(missing.sorted().map { String(format: "U+%04X", $0) })")
    }
}

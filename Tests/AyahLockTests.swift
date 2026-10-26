import AVFoundation
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
        XCTAssertLessThan(store.arabic(2, 1).count, 15, "2:1 should be just Alif-Lam-Mim: \(store.arabic(2, 1))")
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

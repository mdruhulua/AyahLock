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

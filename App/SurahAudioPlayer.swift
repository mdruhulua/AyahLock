import AVFoundation
import Foundation
import MediaPlayer

/// Plays a surah ayah by ayah from any starting ayah. Uses saved audio when
/// available and streams the rest. Also saves whole surahs for offline use.
@MainActor
final class SurahAudioPlayer: ObservableObject {
    static let shared = SurahAudioPlayer()

    struct DownloadState: Equatable {
        let surah: Int
        let reciterID: String
        var done: Int
        var total: Int
    }

    @Published private(set) var surah: Int?
    @Published private(set) var currentAyah: Int?     // nil while the Bismillah plays
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var download: DownloadState?

    var hasSession: Bool { surah != nil }

    private let player = AVQueuePlayer()
    private var ayahForItem: [ObjectIdentifier: Int] = [:]   // 0 = Bismillah
    private var itemObserver: NSKeyValueObservation?
    private var urlCache: [String: [URL]] = [:]
    private var reciterID = ""
    private var downloadTask: Task<Void, Never>?

    // MARK: - Playback

    func play(surah: Int, from ayah: Int, reciterID: String) async {
        RecitationPlayer.shared.stop()
        stop()
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let plan = try await playlist(surah: surah, from: ayah, reciterID: reciterID)
            ayahForItem = [:]
            for entry in plan {
                let item = AVPlayerItem(url: entry.url)
                ayahForItem[ObjectIdentifier(item)] = entry.ayah
                player.insert(item, after: nil)
            }
            self.surah = surah
            self.reciterID = reciterID

            RecitationPlayer.shared.configureAudioSession()
            RecitationPlayer.shared.configureRemoteCommands()
            itemObserver = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.currentItemChanged() }
            }
            player.play()
            isPlaying = true
            updateNowPlaying()
        } catch {
            lastError = error.localizedDescription
            stop()
        }
    }

    struct PlaylistEntry: Equatable {
        let ayah: Int      // 0 = Bismillah
        let url: URL
    }

    /// What will play, in order: the Bismillah (when starting a surah at ayah 1,
    /// except surahs 1 and 9), then each ayah to the end of the surah.
    func playlist(surah: Int, from ayah: Int, reciterID: String) async throws -> [PlaylistEntry] {
        let count = Surah.all[surah - 1].ayahCount
        let start = min(max(ayah, 1), count)
        var entries: [PlaylistEntry] = []

        if start == 1 && QuranTextStore.showsBismillah(surah) {
            let bismillah: URL
            if let local = QuranAPI.localAudio(reciterID: reciterID, surah: 1, ayah: 1) {
                bismillah = local
            } else {
                bismillah = try await audioURLs(surah: 1, reciterID: reciterID)[0]
            }
            entries.append(PlaylistEntry(ayah: 0, url: bismillah))
        }

        var remote: [URL]?
        for a in start...count {
            if let local = QuranAPI.localAudio(reciterID: reciterID, surah: surah, ayah: a) {
                entries.append(PlaylistEntry(ayah: a, url: local))
            } else {
                if remote == nil { remote = try await audioURLs(surah: surah, reciterID: reciterID) }
                entries.append(PlaylistEntry(ayah: a, url: remote![a - 1]))
            }
        }
        return entries
    }

    func pause() {
        guard hasSession else { return }
        player.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard hasSession else { return }
        player.play()
        isPlaying = true
        updateNowPlaying()
    }

    func stop() {
        itemObserver?.invalidate()
        itemObserver = nil
        player.pause()
        player.removeAllItems()
        ayahForItem = [:]
        let hadSession = hasSession
        surah = nil
        currentAyah = nil
        isPlaying = false
        if hadSession {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    private func currentItemChanged() {
        guard hasSession else { return }
        guard let item = player.currentItem else {
            stop()   // reached the end of the surah
            return
        }
        let ayah = ayahForItem[ObjectIdentifier(item)] ?? 0
        currentAyah = ayah == 0 ? nil : ayah
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let surah else { return }
        let name = Surah.all[surah - 1].name
        let position = currentAyah.map { "Ayah \($0)" } ?? "Bismillah"
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Surah \(name)",
            MPMediaItemPropertyArtist: "\(position) · \(Reciter.name(for: reciterID))",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }

    private func audioURLs(surah: Int, reciterID: String) async throws -> [URL] {
        let key = "\(reciterID)/\(surah)"
        if let cached = urlCache[key] { return cached }
        let urls = try await QuranAPI.audioURLs(surah: surah, reciterID: reciterID)
        urlCache[key] = urls
        return urls
    }

    // MARK: - Offline downloads

    func isDownloaded(surah: Int, reciterID: String) -> Bool {
        (1...Surah.all[surah - 1].ayahCount).allSatisfy {
            QuranAPI.localAudio(reciterID: reciterID, surah: surah, ayah: $0) != nil
        }
    }

    /// Saves every ayah of a surah for this reciter. Already-saved ayahs are skipped.
    func startDownload(surah: Int, reciterID: String) {
        guard download == nil else { return }
        let total = Surah.all[surah - 1].ayahCount
        download = DownloadState(surah: surah, reciterID: reciterID, done: 0, total: total)
        lastError = nil
        downloadTask = Task {
            do {
                let urls = try await audioURLs(surah: surah, reciterID: reciterID)
                for ayah in 1...total {
                    if Task.isCancelled { break }
                    try await QuranAPI.saveAudio(from: urls[ayah - 1], reciterID: reciterID, surah: surah, ayah: ayah)
                    download?.done = ayah
                }
            } catch {
                lastError = "Download stopped: \(error.localizedDescription)"
            }
            download = nil
            downloadTask = nil
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    /// Deletes a surah's saved audio, except files a lock-screen item still uses.
    func deleteDownload(surah: Int, reciterID: String, keeping inUse: Set<String>) {
        for ayah in 1...Surah.all[surah - 1].ayahCount {
            let name = QuranAPI.audioFileName(reciterID: reciterID, surah: surah, ayah: ayah)
            guard !inUse.contains(name) else { continue }
            try? FileManager.default.removeItem(at: SharedStore.shared.audioDirectory.appendingPathComponent(name))
        }
        objectWillChange.send()
    }
}

import ActivityKit
import AVFoundation
import Foundation
import MediaPlayer

/// Plays an item's audio files in order, repeats the whole sequence N times
/// with a gap between repeats, and keeps the lock screen updated.
@MainActor
final class RecitationPlayer: NSObject, ObservableObject {
    static let shared = RecitationPlayer()

    @Published private(set) var isActive = false     // a recitation session is running
    @Published private(set) var isPaused = false
    @Published private(set) var currentRepeat = 0
    @Published private(set) var totalRepeats = 0
    @Published private(set) var currentItem: RecitationItem?

    private var player: AVAudioPlayer?
    private var sequence: [URL] = []   // one repetition: the audio files, then a silent gap
    private var position = 0
    private var settings = PlaybackSettings()
    private var startedAt = Date()
    private var activity: Activity<RecitationActivityAttributes>?
    private var commandsConfigured = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
    }

    // MARK: - Public controls

    func togglePinned() {
        if isActive { stop() } else { playPinned() }
    }

    func playPinned() {
        guard let item = SharedStore.shared.pinned else { return }
        play(item)
    }

    func play(_ item: RecitationItem) {
        stop()
        guard !item.audioFileNames.isEmpty else { return }

        settings = SharedStore.shared.settings
        currentItem = item
        totalRepeats = max(0, settings.repeatCount)
        currentRepeat = 1
        position = 0
        startedAt = Date()

        let dir = SharedStore.shared.audioDirectory
        sequence = item.audioFileNames.map { dir.appendingPathComponent($0) }
        if settings.gapSeconds > 0, let silence = Silence.url(seconds: settings.gapSeconds) {
            sequence.append(silence)
        }

        configureAudioSession()
        configureRemoteCommands()
        isActive = true
        isPaused = false
        playCurrent()
        startActivity()
        updateNowPlaying()
    }

    func pause() {
        guard isActive, !isPaused else { return }
        player?.pause()
        isPaused = true
        updateActivity()
        updateNowPlaying()
    }

    func resume() {
        guard isActive, isPaused else { return }
        player?.play()
        isPaused = false
        updateActivity()
        updateNowPlaying()
    }

    func stop() {
        player?.stop()
        player = nil
        let wasActive = isActive
        isActive = false
        isPaused = false
        currentItem = nil
        currentRepeat = 0
        endActivity()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if wasActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Removes any Live Activity left over from a previous run.
    static func endStaleActivities() async {
        for activity in Activity<RecitationActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: - Sequencing

    private func playCurrent() {
        guard position < sequence.count else { stop(); return }
        do {
            let p = try AVAudioPlayer(contentsOf: sequence[position])
            p.delegate = self
            p.play()
            player = p
        } catch {
            // A missing or broken file: stop rather than loop on an error.
            stop()
        }
    }

    private func advance() {
        guard isActive else { return }
        position += 1
        if position < sequence.count {
            playCurrent()
            return
        }
        // One full repetition finished.
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed > Double(settings.maxMinutes * 60) { stop(); return }
        if totalRepeats != 0 && currentRepeat >= totalRepeats { stop(); return }
        currentRepeat += 1
        position = 0
        updateActivity()
        updateNowPlaying()
        playCurrent()
    }

    // MARK: - System integration

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    private func configureRemoteCommands() {
        guard !commandsConfigured else { return }
        commandsConfigured = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isActive { self.resume() } else { self.playPinned() }
            }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isPaused { self.resume() } else { self.pause() }
            }
            return .success
        }
        center.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    private func updateNowPlaying() {
        guard let item = currentItem else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: "\(state.counterText) · \(item.reciterName)",
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
        ]
    }

    private var state: RecitationActivityAttributes.ContentState {
        .init(currentRepeat: currentRepeat, totalRepeats: totalRepeats, isPlaying: isActive && !isPaused)
    }

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let item = currentItem else { return }
        let attributes = RecitationActivityAttributes(
            title: item.title,
            arabic: item.arabic.clipped(400),
            english: settings.showEnglish && !item.english.isEmpty ? item.english.clipped(300) : nil,
            bengali: settings.showBengali && !item.bengali.isEmpty ? item.bengali.clipped(300) : nil)
        // If iOS refuses (for example when started from the background on some
        // versions), audio still plays; only the lock-screen panel is missing.
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil),
            pushType: nil)
    }

    private func updateActivity() {
        guard let activity else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await activity.update(content) }
    }

    private func endActivity() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        Task { @MainActor in
            switch type {
            case .began:
                self.pause()
            case .ended:
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self.resume()
                }
            @unknown default:
                break
            }
        }
    }
}

extension RecitationPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.advance() }
    }
}

/// Makes short silent WAV files used as the gap between repeats.
/// Playing silence (instead of waiting) keeps the app alive in the background.
enum Silence {
    static func url(seconds: Double) -> URL? {
        let secs = min(max(seconds, 0.1), 10)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(String(format: "silence_%.1f.wav", secs))
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let sampleRate: UInt32 = 8000
        let sampleCount = UInt32(Double(sampleRate) * secs)
        let dataSize = sampleCount * 2  // 16-bit mono

        var data = Data()
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        data.append(contentsOf: Array("RIFF".utf8)); append32(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append32(16)
        append16(1)              // PCM
        append16(1)              // mono
        append32(sampleRate)
        append32(sampleRate * 2) // byte rate
        append16(2)              // block align
        append16(16)             // bits per sample
        data.append(contentsOf: Array("data".utf8)); append32(dataSize)
        data.append(Data(count: Int(dataSize)))

        do { try data.write(to: url) } catch { return nil }
        return url
    }
}

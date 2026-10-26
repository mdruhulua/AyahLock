import SwiftUI

struct ContentView: View {
    @EnvironmentObject var player: RecitationPlayer
    @EnvironmentObject var library: LibraryModel
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                pinnedSection
                settingsSection
                librarySection
                helpSection
            }
            .navigationTitle("AyahLock")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add ayah or dua")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddItemView()
            }
        }
    }

    // MARK: Pinned

    private var pinnedSection: some View {
        Section("Pinned to lock screen") {
            if let item = library.pinned {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title).font(.headline)
                    Text(item.reference + " · " + item.reciterName)
                        .font(.caption).foregroundStyle(.secondary)
                    ArabicText(item.arabic, size: 24)
                    if library.settings.showEnglish, !item.english.isEmpty {
                        Text(item.english).font(.body)
                    }
                    if library.settings.showBengali, !item.bengali.isEmpty {
                        Text(item.bengali).font(.body)
                    }
                    playControls(for: item)
                    if let error = player.lastError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 6)
            } else {
                Text("Tap + to add an ayah or dua. The newest one is pinned automatically.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func playControls(for item: RecitationItem) -> some View {
        HStack(spacing: 16) {
            if player.isActive && player.currentItem?.id == item.id {
                Button {
                    player.isPaused ? player.resume() : player.pause()
                } label: {
                    Label(player.isPaused ? "Resume" : "Pause",
                          systemImage: player.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.borderedProminent)
                Button(role: .destructive) { player.stop() } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                Spacer()
                Text(counterText).font(.subheadline.monospacedDigit())
            } else {
                Button { player.play(item) } label: {
                    Label("Recite", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Text(library.settings.repeatCount == 0 ? "Until stopped" : "× \(library.settings.repeatCount)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var counterText: String {
        player.totalRepeats == 0 ? "Repeat \(player.currentRepeat)" : "\(player.currentRepeat) of \(player.totalRepeats)"
    }

    // MARK: Settings

    private var settingsSection: some View {
        Section("Recitation") {
            Toggle("Repeat until I stop it", isOn: Binding(
                get: { library.settings.repeatCount == 0 },
                set: { library.settings.repeatCount = $0 ? 0 : 7 }))
            if library.settings.repeatCount != 0 {
                Stepper("Repeat \(library.settings.repeatCount) times",
                        value: $library.settings.repeatCount, in: 1...999)
            }
            VStack(alignment: .leading) {
                Text("Pause between repeats: \(library.settings.gapSeconds, specifier: "%.0f") s")
                Slider(value: $library.settings.gapSeconds, in: 0...10, step: 1)
            }
            Stepper("Stop after \(library.settings.maxMinutes) minutes",
                    value: $library.settings.maxMinutes, in: 5...240, step: 5)
            Toggle("Show English meaning", isOn: $library.settings.showEnglish)
            Toggle("Show Bengali meaning", isOn: $library.settings.showBengali)
            Text("Changes apply the next time you press play.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Library

    private var librarySection: some View {
        Section("My ayahs and duas") {
            if library.items.isEmpty {
                Text("Nothing saved yet.").foregroundStyle(.secondary)
            }
            ForEach(library.items) { item in
                Button {
                    library.pin(item)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.title).foregroundStyle(.primary)
                            Text(item.reference).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if item.id == library.pinnedID {
                            Image(systemName: "pin.fill").foregroundStyle(.tint)
                        }
                    }
                }
            }
            .onDelete { library.delete(at: $0) }
        }
    }

    // MARK: Help

    private var helpSection: some View {
        Section("Put it on your lock screen") {
            Text("1. Lock your iPhone, then touch and hold the lock screen.")
            Text("2. Tap Customize, then Lock Screen.")
            Text("3. Tap the widget area below the clock and add “Pinned Ayah/Dua”.")
            Text("4. Tap its play button. iPhone asks for Face ID or your passcode first; then the recitation starts and a panel with the counter appears.")
        }
        .font(.callout)
    }
}

/// Right-to-left Arabic text.
struct ArabicText: View {
    let text: String
    let size: CGFloat

    init(_ text: String, size: CGFloat) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.system(size: size))
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

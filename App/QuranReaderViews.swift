import SwiftUI
import UIKit

typealias AyahRef = QuranTextStore.AyahRef

// MARK: - Home: surah list, search, continue reading

struct QuranHomeView: View {
    @ObservedObject private var store = QuranTextStore.shared
    @ObservedObject private var bookmarks = BookmarkStore.shared
    @State private var query = ""
    @State private var ayahResults: [AyahRef] = []

    var body: some View {
        NavigationStack {
            Group {
                if store.isReady {
                    surahList
                } else {
                    QuranDownloadView()
                }
            }
            .navigationTitle("Quran")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { ReaderSettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Reader settings")
                }
            }
            .navigationDestination(for: AyahRef.self) { ref in
                SurahReaderView(surah: ref.surah, startAyah: ref.ayah)
            }
        }
    }

    private var matchingSurahs: [Surah] {
        let q = QuranTextStore.fold(query.trimmingCharacters(in: .whitespaces))
        if q.isEmpty { return Surah.all }
        if let number = Int(q) { return Surah.all.filter { $0.number == number } }
        return Surah.all.filter { QuranTextStore.fold($0.name).contains(q) }
    }

    private var surahList: some View {
        List {
            if query.isEmpty {
                Section {
                    if let last = store.lastRead {
                        NavigationLink(value: last) {
                            Label("Continue: \(Surah.all[last.surah - 1].name), ayah \(last.ayah)",
                                  systemImage: "book.fill")
                        }
                    }
                    NavigationLink { BookmarksView() } label: {
                        HStack {
                            Label("Bookmarks", systemImage: "bookmark.fill")
                            Spacer()
                            Text("\(bookmarks.bookmarks.count)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !matchingSurahs.isEmpty {
                Section(query.isEmpty ? "Surahs" : "Surahs matching") {
                    ForEach(matchingSurahs) { surah in
                        NavigationLink(value: AyahRef(surah: surah.number, ayah: 1)) {
                            SurahRow(surah: surah)
                        }
                    }
                }
            }
            if !query.isEmpty {
                Section(ayahResults.isEmpty ? "No ayahs found" : "Ayahs containing “\(query)”") {
                    ForEach(ayahResults) { ref in
                        NavigationLink(value: ref) {
                            SearchResultRow(ref: ref)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Surah, number, or words")
        .task(id: query) {
            // Wait until typing pauses, then search the whole Quran.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            ayahResults = store.search(query)
        }
    }
}

private struct SurahRow: View {
    let surah: Surah

    var body: some View {
        HStack(spacing: 12) {
            Text("\(surah.number)")
                .font(.footnote.monospacedDigit())
                .frame(width: 32, height: 32)
                .background(Circle().strokeBorder(.tint))
            VStack(alignment: .leading) {
                Text(surah.name)
                Text("\(surah.ayahCount) ayahs").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SearchResultRow: View {
    @EnvironmentObject var library: LibraryModel
    let ref: AyahRef

    var body: some View {
        let store = QuranTextStore.shared
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Surah.all[ref.surah - 1].name) \(ref.surah):\(ref.ayah)")
                .font(.caption).foregroundStyle(.secondary)
            QuranArabicText(surah: ref.surah, ayah: ref.ayah, size: 20, lineLimit: 1)
            Text(library.settings.showBengali && !library.settings.showEnglish
                 ? store.bengali(ref.surah, ref.ayah) : store.english(ref.surah, ref.ayah))
                .font(.caption).lineLimit(2)
        }
    }
}

// MARK: - First-run download

struct QuranDownloadView: View {
    @ObservedObject private var store = QuranTextStore.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed").font(.system(size: 48)).foregroundStyle(.tint)
            Text("Save the whole Quran on this iPhone")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Downloads the Arabic text with the English and Bengali meanings for all 114 surahs, once. After that, reading works without internet. Recitation audio streams, or you can save surahs for offline listening.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            switch store.state {
            case .downloading(let step, let total):
                ProgressView(value: Double(step - 1), total: Double(total))
                Text(["Arabic text", "English meaning", "Bengali meaning"][min(step, 3) - 1] + " (\(step) of \(total))…")
                    .font(.caption)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                downloadButton(title: "Try again")
            default:
                downloadButton(title: "Download Quran text")
            }

            Text("Source: AlQuran Cloud. English: Saheeh International. Bengali: Muhiuddin Khan.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private func downloadButton(title: String) -> some View {
        Button {
            Task { await store.download() }
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }
}

// MARK: - Surah reader

struct SurahReaderView: View {
    let surah: Int
    let startAyah: Int

    @EnvironmentObject var library: LibraryModel
    @ObservedObject private var store = QuranTextStore.shared
    @ObservedObject private var audio = SurahAudioPlayer.shared
    @State private var visibleAyahs: Set<Int> = []
    @State private var selectedAyah: Int?
    @State private var status: String?
    @State private var isDownloaded = false
    @State private var tafsirFor: AyahRef?
    @State private var bookmarkFor: AyahRef?
    @ObservedObject private var bookmarks = BookmarkStore.shared

    private var info: Surah { Surah.all[surah - 1] }
    private var reciterID: String { library.settings.defaultReciterID }
    private var isPlayingHere: Bool { audio.surah == surah }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if QuranTextStore.showsBismillah(surah) {
                    BismillahHeading()
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 8)
                }
                ForEach(1...info.ayahCount, id: \.self) { ayah in
                    AyahRow(surah: surah, ayah: ayah, isCurrent: isPlayingHere && audio.currentAyah == ayah)
                        .id(ayah)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedAyah = ayah }
                        .onAppear { visibleAyahs.insert(ayah) }
                        .onDisappear { visibleAyahs.remove(ayah) }
                }
            }
            .listStyle(.plain)
            .task {
                if startAyah > 1 {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    proxy.scrollTo(startAyah, anchor: .top)
                }
            }
            .onChange(of: audio.currentAyah) { _, ayah in
                guard isPlayingHere, let ayah else { return }
                withAnimation { proxy.scrollTo(ayah, anchor: .center) }
            }
        }
        .navigationTitle("\(surah). \(info.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { playButton }
            ToolbarItem(placement: .primaryAction) { optionsMenu }
        }
        .safeAreaInset(edge: .bottom) { statusBar }
        .confirmationDialog("Ayah \(surah):\(selectedAyah ?? 0)",
                            isPresented: Binding(get: { selectedAyah != nil }, set: { if !$0 { selectedAyah = nil } }),
                            titleVisibility: .visible) {
            if let ayah = selectedAyah {
                Button("Tafsir (explanation)") { tafsirFor = AyahRef(surah: surah, ayah: ayah) }
                Button(bookmarks.isBookmarked(surah: surah, ayah: ayah) ? "Edit bookmark note" : "Bookmark with note") {
                    bookmarkFor = AyahRef(surah: surah, ayah: ayah)
                }
                Button("Play from here") { Task { await audio.play(surah: surah, from: ayah, reciterID: reciterID) } }
                Button("Pin to lock screen and repeat") { pin(ayah) }
                Button("Copy Arabic") { UIPasteboard.general.string = store.arabic(surah, ayah) }
                Button("Copy with meanings") { UIPasteboard.general.string = copyText(ayah) }
            }
        }
        .sheet(item: $tafsirFor) { ref in
            TafsirView(surah: ref.surah, ayah: ref.ayah)
                .environmentObject(library)
        }
        .sheet(item: $bookmarkFor) { ref in
            NavigationStack { BookmarkEditorView(surah: ref.surah, ayah: ref.ayah) }
                .environmentObject(library)
        }
        .onAppear {
            isDownloaded = audio.isDownloaded(surah: surah, reciterID: reciterID)
            store.lastRead = AyahRef(surah: surah, ayah: startAyah)
        }
        .onDisappear {
            if let first = visibleAyahs.min() {
                store.lastRead = AyahRef(surah: surah, ayah: first)
            }
        }
        .onChange(of: audio.download) { _, _ in
            isDownloaded = audio.isDownloaded(surah: surah, reciterID: reciterID)
        }
        .onChange(of: reciterID) { _, newValue in
            isDownloaded = audio.isDownloaded(surah: surah, reciterID: newValue)
        }
    }

    private var playButton: some View {
        Group {
            if audio.isLoading {
                ProgressView()
            } else if isPlayingHere {
                Button { audio.isPlaying ? audio.pause() : audio.resume() } label: {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(audio.isPlaying ? "Pause" : "Resume")
            } else {
                Button {
                    let from = visibleAyahs.min() ?? 1
                    Task { await audio.play(surah: surah, from: from == 1 ? 1 : from, reciterID: reciterID) }
                } label: { Image(systemName: "play.fill") }
                .accessibilityLabel("Play surah")
            }
        }
    }

    private var optionsMenu: some View {
        Menu {
            Toggle("Show English meaning", isOn: $library.settings.showEnglish)
            Toggle("Show Bengali meaning", isOn: $library.settings.showBengali)
            Picker("Script", selection: $library.settings.script) {
                ForEach(QuranScript.allCases) { Text($0.label).tag($0) }
            }
            Picker("Reciter", selection: $library.settings.defaultReciterID) {
                ForEach(Reciter.all) { Text($0.name).tag($0.id) }
            }
            Section("Arabic text size") {
                Button("Larger") { library.settings.arabicFontSize = min(library.settings.arabicFontSize + 2, 44) }
                Button("Smaller") { library.settings.arabicFontSize = max(library.settings.arabicFontSize - 2, 18) }
            }
            Section("Offline audio") {
                if isDownloaded {
                    Button("Delete saved audio", role: .destructive) {
                        audio.deleteDownload(surah: surah, reciterID: reciterID,
                                             keeping: Set(library.items.flatMap(\.audioFileNames)))
                        isDownloaded = false
                    }
                } else if audio.download?.surah == surah {
                    Button("Cancel download") { audio.cancelDownload() }
                } else {
                    Button("Save this surah for offline") { audio.startDownload(surah: surah, reciterID: reciterID) }
                        .disabled(audio.download != nil)
                }
            }
            if isPlayingHere {
                Button("Stop playback", role: .destructive) { audio.stop() }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        let lines: [String] = [
            audio.download.map { "Saving \(Surah.all[$0.surah - 1].name) for offline: \($0.done) of \($0.total)" },
            audio.lastError,
            status,
        ].compactMap { $0 }
        if !lines.isEmpty {
            VStack(spacing: 2) {
                ForEach(lines, id: \.self) { Text($0) }
            }
            .font(.caption)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
    }

    private func pin(_ ayah: Int) {
        status = "Preparing \(surah):\(ayah)…"
        Task {
            do {
                let item = try await QuranAPI.makeItem(surah: surah, from: ayah, to: ayah,
                                                       reciterID: reciterID, title: "")
                library.add(item)
                status = "Pinned \(info.name) \(ayah). It's now on your lock-screen widget."
            } catch {
                status = "Couldn't pin: \(error.localizedDescription)"
            }
        }
    }

    private func copyText(_ ayah: Int) -> String {
        var parts = [store.arabic(surah, ayah)]
        if library.settings.showEnglish { parts.append(store.english(surah, ayah)) }
        if library.settings.showBengali { parts.append(store.bengali(surah, ayah)) }
        parts.append("(Quran \(surah):\(ayah))")
        return parts.joined(separator: "\n\n")
    }
}

private struct AyahRow: View {
    @EnvironmentObject var library: LibraryModel
    @ObservedObject private var bookmarks = BookmarkStore.shared
    let surah: Int
    let ayah: Int
    let isCurrent: Bool

    var body: some View {
        let store = QuranTextStore.shared
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(surah):\(ayah)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if isCurrent {
                    Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(.tint)
                }
                if bookmarks.isBookmarked(surah: surah, ayah: ayah) {
                    Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(.orange)
                        .accessibilityLabel("Bookmarked")
                }
            }
            QuranArabicText(surah: surah, ayah: ayah)
            if library.settings.showEnglish {
                Text(store.english(surah, ayah)).font(.body)
            }
            if library.settings.showBengali {
                Text(store.bengali(surah, ayah)).font(.body)
            }
            if let note = bookmarks.bookmark(surah: surah, ayah: ayah)?.note, !note.isEmpty {
                Label(note, systemImage: "note.text")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}

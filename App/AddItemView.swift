import SwiftUI
import UniformTypeIdentifiers

/// Add a Quran passage (from a preset or any range) or your own dua.
struct AddItemView: View {
    @EnvironmentObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss

    @State private var surahNumber = 2
    @State private var fromAyah = 255
    @State private var toAyah = 255
    @State private var customTitle = ""
    @State private var reciterID = Reciter.all[0].id
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var surah: Surah { Surah.all[surahNumber - 1] }

    /// Valid "to" values; always a non-empty range even mid-update.
    private var toRange: ClosedRange<Int> {
        let lower = min(max(fromAyah, 1), surah.ayahCount)
        let upper = max(lower, min(surah.ayahCount, lower + QuranAPI.maxRange - 1))
        return lower...upper
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reciter") {
                    Picker("Reciter", selection: $reciterID) {
                        ForEach(Reciter.all) { Text($0.name).tag($0.id) }
                    }
                }

                Section {
                    ForEach(QuranPreset.all) { preset in
                        Button {
                            Task { await add(surahNumber: preset.surah, from: preset.from, to: preset.to, title: preset.title) }
                        } label: {
                            HStack {
                                Text(preset.title)
                                Spacer()
                                Text(preset.from == preset.to ? "\(preset.surah):\(preset.from)" : "\(preset.surah):\(preset.from)–\(preset.to)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isLoading)
                    }
                } header: {
                    Text("Quick picks")
                } footer: {
                    Text("Where a dua is only part of an ayah, the whole ayah is recited.")
                }

                Section("Any ayah or range") {
                    Picker("Surah", selection: $surahNumber) {
                        ForEach(Surah.all) { Text("\($0.number). \($0.name)").tag($0.number) }
                    }
                    .onChange(of: surahNumber) { _, _ in
                        fromAyah = 1
                        toAyah = 1
                    }
                    Stepper("From ayah \(fromAyah)", value: $fromAyah, in: 1...surah.ayahCount)
                        .onChange(of: fromAyah) { _, newValue in
                            toAyah = min(max(toAyah, newValue), newValue + QuranAPI.maxRange - 1, surah.ayahCount)
                        }
                    Stepper("To ayah \(toAyah)", value: $toAyah, in: toRange)
                    TextField("Title (optional)", text: $customTitle)
                    Button {
                        Task { await add(surahNumber: surahNumber, from: fromAyah, to: toAyah, title: customTitle) }
                    } label: {
                        Label("Download and pin", systemImage: "arrow.down.circle")
                    }
                    .disabled(isLoading)
                }

                Section {
                    NavigationLink("Add my own dua") {
                        CustomDuaView { item in
                            library.add(item)
                            dismiss()
                        }
                    }
                } footer: {
                    Text("For duas from hadith (e.g. Hisnul Muslim), type the text and import an audio file you trust.")
                }

                if isLoading {
                    Section { ProgressView("Downloading text and audio…") }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                Section {
                    Text("Text and audio: AlQuran Cloud (api.alquran.cloud). English: Saheeh International. Bengali: Muhiuddin Khan.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear { reciterID = library.settings.defaultReciterID }
            .onChange(of: reciterID) { _, newValue in library.settings.defaultReciterID = newValue }
        }
    }

    private func add(surahNumber: Int, from: Int, to: Int, title: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let item = try await QuranAPI.fetchItem(
                surah: Surah.all[surahNumber - 1], from: from, to: to,
                reciterID: reciterID, title: title)
            library.add(item)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Type in a dua and attach its audio from the Files app.
struct CustomDuaView: View {
    let onSave: (RecitationItem) -> Void

    @State private var title = ""
    @State private var source = ""
    @State private var arabic = ""
    @State private var english = ""
    @State private var bengali = ""
    @State private var audioFileName: String?
    @State private var showingImporter = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Dua") {
                TextField("Title, e.g. Morning protection", text: $title)
                TextField("Source, e.g. Abu Dawud 5088", text: $source)
            }
            Section("Arabic") {
                TextEditor(text: $arabic)
                    .frame(minHeight: 90)
                    .environment(\.layoutDirection, .rightToLeft)
            }
            Section("English meaning (optional)") {
                TextEditor(text: $english).frame(minHeight: 70)
            }
            Section("Bengali meaning (optional)") {
                TextEditor(text: $bengali).frame(minHeight: 70)
            }
            Section {
                Button(audioFileName == nil ? "Choose audio file" : "Replace audio file") {
                    showingImporter = true
                }
                if let audioFileName {
                    Text("Attached: \(audioFileName)").font(.caption)
                }
            } header: {
                Text("Recitation audio")
            } footer: {
                Text("An MP3 or M4A saved in the Files app. The app plays it on repeat.")
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            Button("Save and pin") { save() }
                .disabled(title.isEmpty || arabic.isEmpty || audioFileName == nil)
        }
        .navigationTitle("My dua")
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): importAudio(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }

    private func importAudio(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let name = "dua_\(UUID().uuidString).\(url.pathExtension.isEmpty ? "m4a" : url.pathExtension)"
        let destination = SharedStore.shared.audioDirectory.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            audioFileName = name
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't copy the audio: \(error.localizedDescription)"
        }
    }

    private func save() {
        guard let audioFileName else { return }
        onSave(RecitationItem(
            kind: .customDua,
            title: title,
            reference: source.isEmpty ? "My dua" : source,
            arabic: arabic,
            english: english,
            bengali: bengali,
            audioFileNames: [audioFileName],
            reciterName: "My audio"))
    }
}

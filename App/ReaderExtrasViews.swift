import SwiftUI
import UniformTypeIdentifiers

// MARK: - Arabic text in the chosen script

/// One ayah's Arabic, in Uthmani or IndoPak depending on settings.
/// Falls back to Uthmani if the IndoPak text hasn't been added.
struct QuranArabicText: View {
    @EnvironmentObject var library: LibraryModel
    @ObservedObject private var indopak = IndoPakText.shared
    let surah: Int
    let ayah: Int
    var size: CGFloat? = nil
    var lineLimit: Int? = nil

    var body: some View {
        let s: CGFloat = size ?? CGFloat(library.settings.arabicFontSize)
        Group {
            if library.settings.script == .indopak, let text = indopak.text(surah, ayah) {
                Text(text)
                    .font(.custom(IndoPakText.fontName, fixedSize: s))
                    .lineSpacing(s * 0.45)
            } else {
                Text(QuranTextStore.shared.arabic(surah, ayah))
                    .font(.system(size: s))
                    .lineSpacing(8)
            }
        }
        .lineLimit(lineLimit)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The Bismillah heading in the chosen script.
struct BismillahHeading: View {
    @EnvironmentObject var library: LibraryModel
    @ObservedObject private var indopak = IndoPakText.shared

    var body: some View {
        let s = library.settings.arabicFontSize
        Group {
            if library.settings.script == .indopak, let text = indopak.bismillah {
                Text(text).font(.custom(IndoPakText.fontName, fixedSize: s))
            } else if let text = QuranTextStore.shared.text?.bismillah {
                Text(text).font(.system(size: s))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Tafsir

struct TafsirView: View {
    let surah: Int
    @State private var ayah: Int

    @EnvironmentObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var entry: TafsirEntry?
    @State private var errorMessage: String?
    @State private var isLoading = false

    init(surah: Int, ayah: Int) {
        self.surah = surah
        _ayah = State(initialValue: ayah)
    }

    private var source: TafsirSource { TafsirSource.named(library.settings.tafsirSlug) }
    private var ayahCount: Int { Surah.all[surah - 1].ayahCount }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(Surah.all[surah - 1].name) \(surah):\(ayah)")
                        .font(.caption).foregroundStyle(.secondary)
                    QuranArabicText(surah: surah, ayah: ayah)
                    if library.settings.showBengali && source.language == "English" {
                        Text(QuranTextStore.shared.bengali(surah, ayah)).font(.callout).foregroundStyle(.secondary)
                    } else if library.settings.showEnglish && source.language == "Bengali" {
                        Text(QuranTextStore.shared.english(surah, ayah)).font(.callout).foregroundStyle(.secondary)
                    }
                    Divider()
                    sourceMenu
                    content
                }
                .padding()
            }
            .navigationTitle("Tafsir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        ayah = max(1, (entry?.fromAyah ?? ayah) - 1)
                    } label: { Label("Previous ayah", systemImage: "chevron.left") }
                    .disabled((entry?.fromAyah ?? ayah) <= 1)
                    Spacer()
                    Button {
                        ayah = min(ayahCount, (entry?.toAyah ?? ayah) + 1)
                    } label: { Label("Next ayah", systemImage: "chevron.right") }
                    .disabled((entry?.toAyah ?? ayah) >= ayahCount)
                }
            }
            .task(id: "\(source.slug)/\(ayah)") { await load() }
        }
    }

    private var sourceMenu: some View {
        Menu {
            ForEach(["English", "Bengali"], id: \.self) { language in
                Section(language) {
                    ForEach(TafsirSource.all.filter { $0.language == language }) { s in
                        Button {
                            library.settings.tafsirSlug = s.slug
                        } label: {
                            if s.slug == source.slug { Label(s.name, systemImage: "checkmark") } else { Text(s.name) }
                        }
                    }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(source.name).font(.headline)
                    Text("\(source.author) · \(source.language)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
        }
        .accessibilityLabel("Choose tafsir")
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Loading tafsir…").frame(maxWidth: .infinity)
        } else if let errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn't load the tafsir. It needs internet the first time each surah is opened.")
                Text(errorMessage).font(.caption).foregroundStyle(.secondary)
                Button("Try again") { Task { await load() } }
            }
            .foregroundStyle(.red)
        } else if let entry {
            if entry.text.isEmpty {
                Text("This tafsir has no explanation for this ayah.").foregroundStyle(.secondary)
            } else {
                if entry.fromAyah != entry.toAyah {
                    Label("Explains ayahs \(entry.fromAyah)–\(entry.toAyah) together", systemImage: "text.alignleft")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(entry.text)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            entry = try await TafsirStore.shared.entry(slug: source.slug, surah: surah, ayah: ayah)
        } catch {
            entry = nil
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Bookmarks

struct BookmarkEditorView: View {
    let surah: Int
    let ayah: Int

    @EnvironmentObject var library: LibraryModel
    @ObservedObject private var bookmarks = BookmarkStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var loaded = false

    private var existing: Bookmark? { bookmarks.bookmark(surah: surah, ayah: ayah) }

    var body: some View {
        Form {
            Section {
                Text("\(Surah.all[surah - 1].name) \(surah):\(ayah)").font(.caption).foregroundStyle(.secondary)
                QuranArabicText(surah: surah, ayah: ayah, size: 22)
                if library.settings.showEnglish {
                    Text(QuranTextStore.shared.english(surah, ayah)).font(.callout)
                }
                if library.settings.showBengali {
                    Text(QuranTextStore.shared.bengali(surah, ayah)).font(.callout)
                }
            }
            Section {
                TextEditor(text: $note).frame(minHeight: 140)
            } header: {
                Text("Your note")
            } footer: {
                Text("Optional. Notes are saved only on this iPhone.")
            }
            if existing != nil {
                Section {
                    Button("Remove bookmark", role: .destructive) {
                        bookmarks.delete(surah: surah, ayah: ayah)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(existing == nil ? "Add bookmark" : "Edit bookmark")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    bookmarks.save(surah: surah, ayah: ayah, note: note)
                    dismiss()
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            note = existing?.note ?? ""
            loaded = true
        }
    }
}

struct BookmarksView: View {
    @EnvironmentObject var library: LibraryModel
    @ObservedObject private var bookmarks = BookmarkStore.shared
    @State private var order: BookmarkStore.Order = .quran
    @State private var query = ""
    @State private var editing: Bookmark?

    var body: some View {
        let items = bookmarks.filtered(query, order: order)
        List {
            if bookmarks.bookmarks.isEmpty {
                ContentUnavailableView(
                    "No bookmarks yet",
                    systemImage: "bookmark",
                    description: Text("In the reader, tap an ayah and choose “Bookmark with note”."))
            } else {
                Picker("Order", selection: $order) {
                    ForEach(BookmarkStore.Order.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                ForEach(items) { b in
                    NavigationLink(value: b.ref) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(b.title).font(.subheadline.bold())
                            QuranArabicText(surah: b.surah, ayah: b.ayah, size: 18, lineLimit: 1)
                            if !b.note.isEmpty {
                                Text(b.note).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                            }
                            Text(b.updated, format: .dateTime.day().month().year())
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { bookmarks.delete(ids: [b.id]) }
                        Button("Edit note") { editing = b }.tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("Bookmarks")
        .searchable(text: $query, prompt: "Search notes and surahs")
        .toolbar {
            if !bookmarks.bookmarks.isEmpty {
                ShareLink(item: bookmarks.exportText(store: QuranTextStore.shared)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share all bookmarks")
            }
        }
        .sheet(item: $editing) { b in
            NavigationStack { BookmarkEditorView(surah: b.surah, ayah: b.ayah) }
                .environmentObject(library)
        }
    }
}

// MARK: - Reader settings

struct ReaderSettingsView: View {
    @EnvironmentObject var library: LibraryModel
    @ObservedObject private var indopak = IndoPakText.shared
    @ObservedObject private var tafsir = TafsirStore.shared
    @State private var showingImporter = false
    @State private var importMessage: String?

    var body: some View {
        Form {
            Section {
                Picker("Script", selection: $library.settings.script) {
                    ForEach(QuranScript.allCases) { Text($0.label).tag($0) }
                }
                QuranArabicText(surah: 112, ayah: 1, size: 26)
                if library.settings.script == .indopak && !indopak.isAvailable {
                    Text("The IndoPak text hasn't been added yet, so Uthmani is shown. Download “Digital Khatt Indopak Script – Ayah by Ayah” as JSON from qul.tarteel.ai (free account), then import it here.")
                        .font(.caption)
                    Link("Open the download page", destination: URL(string: "https://qul.tarteel.ai/resources/quran-script/566")!)
                }
                if !indopak.isAvailable || library.settings.script == .indopak {
                    Button(indopak.isAvailable ? "Replace IndoPak text file" : "Import IndoPak text file") {
                        showingImporter = true
                    }
                }
                if let importMessage {
                    Text(importMessage).font(.caption)
                }
            } header: {
                Text("Arabic script")
            } footer: {
                Text("The lock-screen widget always uses Uthmani.")
            }

            Section("Text") {
                VStack(alignment: .leading) {
                    Text("Arabic size: \(Int(library.settings.arabicFontSize))")
                    Slider(value: $library.settings.arabicFontSize, in: 18...44, step: 1)
                }
                Toggle("Show English meaning", isOn: $library.settings.showEnglish)
                Toggle("Show Bengali meaning", isOn: $library.settings.showBengali)
            }

            Section("Recitation") {
                Picker("Reciter", selection: $library.settings.defaultReciterID) {
                    ForEach(Reciter.all) { Text($0.name).tag($0.id) }
                }
            }

            Section {
                Picker("Default tafsir", selection: $library.settings.tafsirSlug) {
                    ForEach(TafsirSource.all) { Text("\($0.name) (\($0.language))").tag($0.slug) }
                }
                ForEach(TafsirSource.all) { source in
                    tafsirRow(source)
                }
                if let error = tafsir.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Tafsir")
            } footer: {
                Text("Each surah's tafsir is kept on the phone after you first open it. “Save all” stores the whole tafsir for offline reading.")
            }

            Section {
                NavigationLink("Sources and credits") { CreditsView() }
            }
        }
        .navigationTitle("Reader settings")
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    try indopak.importFile(from: url)
                    library.settings.script = .indopak
                    importMessage = "IndoPak text added."
                } catch {
                    importMessage = error.localizedDescription
                }
            case .failure(let error):
                importMessage = error.localizedDescription
            }
        }
    }

    private func tafsirRow(_ source: TafsirSource) -> some View {
        let saved = tafsir.savedSurahCount(slug: source.slug)
        let active = tafsir.fullDownload?.slug == source.slug
        return HStack {
            VStack(alignment: .leading) {
                Text(source.name)
                Text(active ? "Saving… \(tafsir.fullDownload?.done ?? saved) of 114" : "\(source.language) · saved: \(saved) of 114 surahs")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if active {
                Button("Stop") { tafsir.cancelDownload() }
            } else if saved == 114 {
                Button("Delete", role: .destructive) { tafsir.deleteAll(slug: source.slug) }
            } else {
                Button("Save all") { tafsir.downloadAll(slug: source.slug) }
                    .disabled(tafsir.fullDownload != nil)
            }
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Credits

struct CreditsView: View {
    var body: some View {
        List {
            Section("Quran text and translations") {
                credit("Arabic (Uthmani), English and Bengali", "AlQuran Cloud, from the Tanzil Project. English: Saheeh International. Bengali: Muhiuddin Khan.", "https://alquran.cloud")
                credit("Tanzil Project", "Quran text verified by the Tanzil Project, used with attribution.", "https://tanzil.net")
            }
            Section("Recitation") {
                credit("Recitation audio", "Streamed from the Islamic Network CDN via AlQuran Cloud. Audio copyrights remain with their owners.", "https://alquran.cloud/cdn")
            }
            Section("Tafsir") {
                ForEach(TafsirSource.all) { s in
                    Text("\(s.name) — \(s.author) (\(s.language))").font(.callout)
                }
                credit("Tafsir data", "From the open tafsir_api dataset, originally compiled from Quran.com and the Quranic Universal Library.", "https://github.com/spa5k/tafsir_api")
            }
            Section("IndoPak script") {
                credit("Digital Khatt IndoPak font", "© Amine Anane and Tarteel Inc., SIL Open Font License 1.1. TrueType conversion from the Waqfah project.", "https://github.com/DigitalKhatt/indopakfont")
                NavigationLink("Font licence (SIL OFL 1.1)") { LicenceTextView() }
                credit("IndoPak text", "“Digital Khatt Indopak Script”, Quranic Universal Library by Tarteel AI.", "https://qul.tarteel.ai/resources/quran-script/566")
            }
        }
        .navigationTitle("Sources and credits")
    }

    private func credit(_ title: String, _ detail: String, _ link: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            Text(detail).font(.caption)
            if let url = URL(string: link) { Link(link, destination: url).font(.caption) }
        }
    }
}

private struct LicenceTextView: View {
    var body: some View {
        ScrollView {
            Text(Self.text)
                .font(.system(.footnote, design: .monospaced))
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle("SIL OFL 1.1")
    }

    static var text: String {
        guard let url = Bundle.main.url(forResource: "DigitalKhattIndoPak-OFL", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Licence file missing."
        }
        return text
    }
}

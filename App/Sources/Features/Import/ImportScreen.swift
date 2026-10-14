import CloudSync
import Foundation
import Importer
import Model
import SwiftUI
import UniformTypeIdentifiers

/// Importing a spreadsheet or CSV export (UI.md, "Import"; IMPORT.md, "Steps"),
/// or a broker's transactions (IMPORT.md, "Broker transactions": a Types step
/// after Columns), or a bank statement (IMPORT.md, "Bank statements": File,
/// with the account, then Income).
///
/// - **Mac and iPad:** every step, along the top: File, Format, Columns,
///   Types when the file needs it, Accounts, Preview and Done; for a bank
///   statement File, Income, Preview and Done, with Format and Columns in
///   a sheet. The page keeps its import while you visit other pages.
/// - **iPhone:** a sheet that starts as "Import with profile…": the file and
///   a saved profile, the preview, Done. "Set up the columns step by step"
///   switches to every step, for a file no profile fits.
///
/// ⌘⇧I, the sidebar's Import… and dropping a CSV on the window create it,
/// with the file if there is one; the sidebar's file is taken from
/// `navigation.pendingImport` once read. First launch pushes it on its own
/// stack with `close`, on every device. A check-in opens it in a sheet with
/// `close`, the statements chosen and its date (UI.md, "Statements first").
struct ImportScreen: View {
    let file: URL?
    /// Files chosen before the screen opened (a check-in's *Add
    /// Statements…*), read when it first appears.
    let files: [URL]
    /// Closes the screen when it's pushed on another flow's stack (first
    /// launch's accounts step): it then has an import of its own, as the
    /// iPhone's sheet does, and *Close* or *Done* calls it. `nil` for the
    /// sheet and the page.
    let close: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    /// The import of the iPhone's sheet, or of a screen with `close`; the
    /// Mac and iPad page use ``ImportController/page``.
    @State private var sheetModel = ImportController()
    @State private var isChoosingFile = false
    @State private var didStart = false
    /// The file ``take(_:)`` read last. Its task runs again whenever the
    /// screen reappears, e.g. from *Sync & backups* pushed over it, and
    /// mustn't read the file again: that would start the import over.
    @State private var takenFile: URL?

    init(file: URL? = nil, close: (() -> Void)? = nil) {
        self.file = file
        files = []
        self.close = close
    }

    /// The import of a check-in on `checkIn`: its own, opening `files`;
    /// *Close* or *Done* calls `close`.
    init(files: [URL], checkIn: CalendarDate, close: @escaping () -> Void) {
        file = nil
        self.files = files
        self.close = close
        _sheetModel = State(initialValue: ImportController(checkIn: checkIn))
    }

    /// The import on screen: with tabs (iPhone) the screen is a sheet with
    /// its own, and so is a screen with `close`; with a sidebar it's a page
    /// that keeps its import.
    private var model: ImportController {
        isSheet ? sheetModel : ImportController.page
    }

    /// Whether the screen has an import of its own and a *Close* button.
    private var isSheet: Bool { close != nil || navigation.layout == .tabs }

    private var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        stepContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.page)
            .importBars(model: model, isCompact: isCompact)
            .environment(\.importClose, closeAction)
            .navigationTitle("Import")
            #if os(macOS)
            .personalNavigationSubtitle(model.flow.fileName ?? "")
            #endif
            .toolbar {
                if isSheet {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(model.flow.step == .done ? "Done" : "Close") {
                            closeAction?()
                        }
                    }
                }
            }
            .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: ImportFileReader.contentTypes,
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    guard !urls.isEmpty else { return }
                    Task { await open(urls) }
                case .failure(let error):
                    model.errorMessage = error.localizedDescription
                }
            }
            .onAppear { start() }
            .task(id: file) {
                await take(file)
            }
            .onChange(of: library.revision) { _, _ in
                model.libraryChanged(library.library)
            }
            .alert("Something went wrong", isPresented: isShowingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
    }

    private var stepContent: some View {
        ImportStepContent(model: model, isCompact: isCompact, chooseFile: { isChoosingFile = true }, openFiles: { urls in
            Task { await open(urls) }
        })
    }

    /// Closes the screen when it has an import of its own; `nil` for the page.
    private var closeAction: (@MainActor () -> Void)? {
        guard isSheet else { return nil }
        if let close { return { close() } }
        let navigation = navigation
        return { navigation.sheet = nil }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    /// First appearance: the preview compares with this library, and on
    /// iPhone a new import starts as "Import with profile…".
    private func start() {
        model.libraryChanged(library.library)
        guard !didStart else { return }
        didStart = true
        if !model.flow.hasFile, model.flow.step == .file {
            // A check-in's statements show every step: their lines are answered on Income.
            model.flow.setGuided(isCompact && model.flow.checkIn == nil)
        }
        if !files.isEmpty {
            let files = self.files
            Task { await open(files) }
        }
    }

    /// Reads the file the screen was created with, once, then takes it from the navigation.
    private func take(_ file: URL?) async {
        guard file != takenFile else { return }
        takenFile = file
        guard let file else { return }
        await open([file])
        navigation.clearPendingImport(file)
    }

    /// Reads one file, or several bank statements to import together. A
    /// file of several that can't be read is said so; the others open.
    private func open(_ urls: [URL]) async {
        let model = self.model
        guard urls.count > 1 else {
            guard let url = urls.first else { return }
            do {
                let data = try await ImportFileReader.read(url)
                model.open(data, fileName: url.lastPathComponent)
            } catch {
                model.openFailed(fileName: url.lastPathComponent, message: error.localizedDescription)
            }
            return
        }
        var files: [(name: String, data: Data)] = []
        var failures: [String] = []
        for url in urls {
            do {
                let data = try await ImportFileReader.read(url)
                files.append((url.lastPathComponent, data))
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        model.open(files: files)
        if !failures.isEmpty {
            model.errorMessage = "Some files couldn't be opened. " + failures.joined(separator: " ")
        }
    }
}

/// The current step's page.
struct ImportStepContent: View {
    let model: ImportController
    let isCompact: Bool
    /// Shows the file importer.
    let chooseFile: () -> Void
    /// Reads the files dropped on the File step.
    let openFiles: ([URL]) -> Void

    var body: some View {
        switch model.flow.step {
        case .file:
            ImportFileStep(model: model, isCompact: isCompact, chooseFile: chooseFile, openFiles: openFiles)
        case .format:
            ImportFormatStep(model: model)
        case .columns:
            ImportColumnsStep(model: model, isCompact: isCompact)
        case .types:
            ImportTypesStep(model: model)
        case .classify:
            ImportClassifyStep(model: model)
        case .accounts:
            ImportAccountsStep(model: model)
        case .preview:
            ImportPreviewStep(model: model)
        case .done:
            ImportDoneStep(model: model)
        }
    }
}

// MARK: - Steps along the top

/// The steps along the top: done ones with a check, the current one filled.
/// Tap a step to go back to it (or forward, once a file is read).
struct ImportStepBar: View {
    let model: ImportController

    var body: some View {
        let flow = model.flow
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.xs) {
                ForEach(Array(flow.steps.enumerated()), id: \.element) { index, step in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Palette.mutedInk)
                            .accessibilityHidden(true)
                    }
                    Button {
                        model.flow.show(step)
                    } label: {
                        ImportStepLabel(number: index + 1, title: step.title,
                                        progress: progress(of: step, current: flow.step))
                    }
                    .buttonStyle(.plain)
                    .disabled(!flow.canShow(step))
                }
            }
            .padding(.horizontal, Metrics.l)
            .padding(.vertical, Metrics.s)
        }
        .background(.bar)
    }

    private func progress(of step: ImportStep, current: ImportStep) -> ImportStepLabel.Progress {
        if step == current { return .current }
        return step < current ? .done : .upcoming
    }
}

/// One step: its number (a check once done) and its name.
private struct ImportStepLabel: View {
    enum Progress {
        case done
        case current
        case upcoming
    }

    let number: Int
    let title: String
    let progress: Progress

    var body: some View {
        HStack(spacing: Metrics.xs) {
            ZStack {
                Circle()
                    .fill(progress == .upcoming ? Color.clear : Palette.accent)
                Circle()
                    .strokeBorder(progress == .upcoming ? Palette.border : Palette.accent, lineWidth: 1)
                if progress == .done {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.white)
                } else {
                    Text(verbatim: "\(number)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(progress == .current ? Color.white : Palette.secondaryInk)
                }
            }
            .frame(width: 20, height: 20)
            Text(title)
                .font(.subheadline.weight(progress == .current ? .semibold : .regular))
                .foregroundStyle(progress == .upcoming ? Palette.secondaryInk : Palette.ink)
        }
        .padding(.horizontal, Metrics.s)
        .padding(.vertical, Metrics.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Step \(number), \(title)"))
        .accessibilityValue(Text(progress == .current ? "Current" : progress == .done ? "Done" : ""))
    }
}

// MARK: - Back and Continue

/// Back, and Continue (Import on the preview; Import another file when done).
struct ImportBottomBar: View {
    let model: ImportController

    @Environment(LibraryStore.self) private var library

    var body: some View {
        let flow = model.flow
        HStack(spacing: Metrics.m) {
            if flow.previousStep != nil {
                Button {
                    model.flow.goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(model.isWorking)
            }
            Spacer(minLength: Metrics.s)
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            switch flow.step {
            case .preview:
                Button("Import") {
                    Task { await model.runImport(in: library) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!flow.blockers.isEmpty || model.isWorking || !library.canEdit)
            case .done:
                Button(flow.isBatch ? "Import Other Files" : "Import Another File") {
                    model.startOver()
                }
                .disabled(model.isWorking)
            default:
                if let hint = flow.continueHint {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(Palette.warning)
                        .privacySensitiveInFeedback(flow.isBatch)
                }
                Button("Continue") {
                    model.flow.goForward()
                }
                .buttonStyle(.borderedProminent)
                .disabled(flow.nextStep == nil)
            }
        }
        .padding(.horizontal, Metrics.l)
        .padding(.vertical, Metrics.m)
        .background(.bar)
    }
}

// MARK: - Reading files

/// Reads a file the user chose, dropped or opened from Files, off the main
/// thread, with security-scoped access and file coordination (so a file
/// in iCloud Drive is downloaded first).
enum ImportFileReader {
    /// CSV, TSV and plain text.
    static let contentTypes: [UTType] = [.commaSeparatedText, .tabSeparatedText, .delimitedText, .plainText]

    static func read(_ url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try readNow(url)
        }.value
    }

    private static func readNow(_ url: URL) throws -> Data {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped { url.stopAccessingSecurityScopedResource() }
        }
        return try CoordinatedFileAccess().readData(at: url)
    }
}

#Preview("Import · file") {
    NavigationStack {
        ImportScreen()
    }
    .previewEnvironment()
}

#Preview("Import · a dropped file") {
    NavigationStack {
        ImportPreviewHost(step: .columns)
    }
    .previewEnvironment()
}

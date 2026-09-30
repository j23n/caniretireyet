import CloudSync
import Foundation
import Importer
import Model
import SwiftUI
import UniformTypeIdentifiers

/// Importing a spreadsheet or CSV export (UI.md, "Import"; IMPORT.md, "Steps"),
/// a broker's transactions (IMPORT.md, "Broker transactions": a Types step
/// after Columns), or ledger-cli / hledger journals (IMPORT.md, "Ledger
/// journals"): their steps are Files, Accounts, Commodities, Preview and Done.
///
/// - **Mac and iPad:** every step, along the top: File, Format, Columns,
///   Accounts, Preview and Done. The page keeps its import while you visit
///   other pages.
/// - **iPhone:** a sheet that starts as "Import with profile…": the file and
///   a saved profile, the preview, Done. "Set up the columns step by step"
///   switches to every step, for a file no profile fits.
///
/// ⌘⇧I, the sidebar's Import… and dropping a CSV on the window create it,
/// with the file if there is one; the sidebar's file is taken from
/// `navigation.pendingImport` once read.
struct ImportScreen: View {
    let file: URL?

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    /// The iPhone sheet's own import; the Mac and iPad page use ``ImportController/page``.
    @State private var sheetModel = ImportController()
    @State private var isChoosingFile = false
    @State private var didStart = false

    init(file: URL? = nil) {
        self.file = file
    }

    /// The import on screen: with tabs (iPhone) the screen is a sheet with
    /// its own; with a sidebar it's a page that keeps its import.
    private var model: ImportController {
        isSheet ? sheetModel : ImportController.page
    }

    private var isSheet: Bool { navigation.layout == .tabs }

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
            .safeAreaInset(edge: .top, spacing: 0) {
                ImportStepBar(model: model)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ImportBottomBar(model: model)
            }
            .navigationTitle("Import")
            #if os(macOS)
            .navigationSubtitle(model.flow.fileName ?? "")
            #endif
            .toolbar {
                if isSheet {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(model.flow.step == .done ? "Done" : "Close") {
                            navigation.sheet = nil
                        }
                    }
                }
            }
            .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: ImportFileReader.contentTypes,
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
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
        ImportStepContent(model: model, isCompact: isCompact, chooseFile: { isChoosingFile = true }, openFile: { url in
            Task { await open([url]) }
        }, openFiles: { urls in
            Task { await open(urls) }
        })
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
            model.flow.setGuided(isCompact)
        }
    }

    /// Reads the file the screen was created with, then takes it from the navigation.
    private func take(_ file: URL?) async {
        guard let file else { return }
        await open([file] + navigation.takeAdditionalImportFiles())
        if navigation.pendingImport == file {
            _ = navigation.takePendingImport()
        }
    }

    /// Journals (one or more) start a journal import; otherwise the first
    /// file is read as a spreadsheet.
    private func open(_ urls: [URL]) async {
        let journals = urls.filter(LedgerFiles.isJournal)
        if !journals.isEmpty {
            await model.openLedger(journals)
        } else if let url = urls.first {
            await open(url)
        }
    }

    private func open(_ url: URL) async {
        let model = self.model
        do {
            let data = try await ImportFileReader.read(url)
            model.open(data, fileName: url.lastPathComponent)
        } catch {
            model.openFailed(fileName: url.lastPathComponent, message: error.localizedDescription)
        }
    }
}

/// The current step's page.
struct ImportStepContent: View {
    let model: ImportController
    let isCompact: Bool
    /// Shows the file importer.
    let chooseFile: () -> Void
    /// Reads a file dropped on the File step.
    let openFile: (URL) -> Void
    /// Reads files dropped together (journals).
    var openFiles: ([URL]) -> Void = { _ in }

    var body: some View {
        switch model.flow.step {
        case .file:
            if model.flow.isLedger {
                LedgerFilesStep(model: model, chooseFiles: chooseFile, openFiles: openFiles)
            } else {
                ImportFileStep(model: model, chooseFile: chooseFile, openFile: openFile, openFiles: openFiles)
            }
        case .format:
            ImportFormatStep(model: model)
        case .columns:
            ImportColumnsStep(model: model, isCompact: isCompact)
        case .types:
            ImportTypesStep(model: model)
        case .accounts:
            if model.flow.isLedger {
                LedgerAccountsStep(model: model)
            } else {
                ImportAccountsStep(model: model)
            }
        case .commodities:
            LedgerCommoditiesStep(model: model)
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
                Button("Import Another File") {
                    model.startOver()
                }
                .disabled(model.isWorking)
            default:
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
    /// CSV, TSV and plain text, and ledger journals.
    static let contentTypes: [UTType] = [.commaSeparatedText, .tabSeparatedText, .delimitedText, .plainText]
        + LedgerFileTypes.contentTypes

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

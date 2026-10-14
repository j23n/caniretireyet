import CloudSync
import Foundation
import Importer
import Model
import SwiftUI
import UniformTypeIdentifiers

/// Importing a spreadsheet or CSV export (UI.md, "Import"; IMPORT.md, "Steps"),
/// or a broker's transactions (IMPORT.md, "Broker transactions": a Types step
/// after Columns), or bank statements (IMPORT.md, "Bank statements": Files,
/// Income and Review, with how a file is read in a sheet).
///
/// - **Mac and iPad:** a page. The steps are a capsule in the toolbar's
///   middle, with *Add Files…* on the Files step; the window's subtitle
///   says what's open ("3 statements"). A bar at the bottom says why
///   Continue waits, with *Cancel* (which starts over) on the first step
///   and *Back* on the others. The page keeps its import while you visit
///   other pages.
/// - **iPhone:** a sheet. The navigation bar has *Cancel* (or *Back* to the
///   step before), "Step 1 of 3" and *Next*, under it the step's large
///   title; Review imports with a button at the bottom. One file that
///   isn't a bank statement starts as "Import with profile…": the file and
///   a saved profile, the preview, Done.
///
/// ⌘⇧I, the sidebar's Import… and dropping a CSV on the window create it,
/// with the file if there is one; the sidebar's file is taken from
/// `navigation.pendingImport` once read. First launch pushes it on its own
/// stack with `close`, on every device. A check-in opens it in a sheet with
/// `close`, for the check-in's date (UI.md, "Check-in").
struct ImportScreen: View {
    let file: URL?
    /// Closes the screen when it's pushed on another flow's stack (first
    /// launch's accounts step): it then has an import of its own, as the
    /// iPhone's sheet does, and *Cancel* or *Done* calls it. `nil` for the
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
    /// What the files are before any is read: the Files step's switch, and
    /// the steps along the top until a file says.
    @State private var kindBeforeFiles: ImportFilesKind = .statements
    /// The file ``take(_:)`` read last. Its task runs again whenever the
    /// screen reappears, e.g. from *Sync & backups* pushed over it, and
    /// mustn't read the file again: that would start the import over.
    @State private var takenFile: URL?

    init(file: URL? = nil, close: (() -> Void)? = nil) {
        self.file = file
        self.close = close
    }

    /// An import for the check-in on `date` (UI.md, "Check-in"): bank
    /// statements are read through that date. It writes as any import
    /// does; *Close* calls `close`.
    init(checkIn date: CalendarDate, close: @escaping () -> Void) {
        file = nil
        self.close = close
        _sheetModel = State(initialValue: ImportController(checkIn: date))
    }

    /// The import on screen: with tabs (iPhone) the screen is a sheet with
    /// its own, and so is a screen with `close`; with a sidebar it's a page
    /// that keeps its import.
    private var model: ImportController {
        isSheet ? sheetModel : ImportController.page
    }

    /// Whether the screen has an import of its own, which *Cancel* closes.
    private var isSheet: Bool { close != nil || navigation.layout == .tabs }

    private var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    /// Whether the steps are a capsule in a strip above the page rather
    /// than in the toolbar: a Mac sheet has no toolbar to hold them.
    private var showsStepStrip: Bool {
        #if os(macOS)
        return isSheet && model.flow.step != .done
        #else
        return false
        #endif
    }

    var body: some View {
        stepContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.page)
            .safeAreaInset(edge: .top, spacing: 0) {
                if showsStepStrip, model.flow.showsImportBars {
                    ImportStepBar(model: model, kindBeforeFiles: kindBeforeFiles)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Metrics.s)
                        .background(.bar)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.flow.step == .preview, model.flow.layout == .statement {
                    ImportReviewBottomBar(model: model, isCompact: isCompact)
                } else if model.flow.showsImportBars {
                    ImportBottomBar(model: model, isCompact: isCompact, cancel: cancel)
                }
            }
            .environment(\.importClose, closeAction)
            .modifier(ImportTitle(flow: model.flow, isCompact: isCompact))
            .toolbar { toolbar }
            .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: ImportFileReader.contentTypes,
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    guard !urls.isEmpty else { return }
                    Task { await add(urls) }
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        let flow = model.flow
        if isCompact {
            if flow.step == .done {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: cancel)
                }
            } else {
                ToolbarItem(placement: .cancellationAction) {
                    if let previous = flow.previousStep {
                        Button {
                            model.flow.goBack()
                        } label: {
                            Label(previous.title, systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                        }
                        .disabled(model.isWorking)
                    } else {
                        Button("Cancel", action: cancel)
                    }
                }
                if let text = flow.stepText(beforeFiles: kindBeforeFiles) {
                    ToolbarItem(placement: .principal) {
                        Text(text)
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                if flow.step < .preview {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Next") {
                            model.flow.goForward()
                        }
                        .fontWeight(.semibold)
                        .disabled(flow.nextStep == nil)
                    }
                }
            }
        } else {
            if flow.step != .done, !showsStepStrip {
                ToolbarItem(placement: .principal) {
                    ImportStepBar(model: model, kindBeforeFiles: kindBeforeFiles)
                }
            }
            if flow.step == .file {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Files…", systemImage: "plus") {
                        isChoosingFile = true
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
            if isSheet, flow.step == .done {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: cancel)
                }
            }
        }
    }

    private var stepContent: some View {
        ImportStepContent(model: model, isCompact: isCompact, chooseFile: { isChoosingFile = true },
                          openFiles: { urls in Task { await add(urls) } },
                          kindBeforeFiles: $kindBeforeFiles)
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

    /// *Cancel*: a sheet, or a screen pushed with `close`, closes; the page
    /// starts over.
    private func cancel() {
        if let close {
            close()
        } else if isSheet {
            navigation.sheet = nil
        } else {
            model.startOver()
        }
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

    /// Reads the file the screen was created with, once, then takes it from the navigation.
    private func take(_ file: URL?) async {
        guard file != takenFile else { return }
        takenFile = file
        guard let file else { return }
        await open([file])
        navigation.clearPendingImport(file)
    }

    /// Starts over with one file, or several bank statements to import
    /// together. A file of several that can't be read is said so; the
    /// others open.
    private func open(_ urls: [URL]) async {
        let model = self.model
        let (files, failures) = await read(urls)
        if let file = files.first, files.count == 1 {
            model.open(file.data, fileName: file.name)
        } else if !files.isEmpty {
            model.open(files: files)
        } else if urls.count == 1, let failure = failures.first {
            model.openFailed(fileName: failure.name, message: failure.message)
            return
        }
        report(failures)
    }

    /// Adds files chosen with *Add Files…* or dropped: bank statements join
    /// those listed, and a broker's transactions are read one file at a
    /// time. With nothing open, or another kind of file, they're opened as
    /// the Files step's switch says.
    private func add(_ urls: [URL]) async {
        let model = self.model
        let (files, failures) = await read(urls)
        if !files.isEmpty {
            if model.flow.step != .done, let kind = model.flow.filesKind {
                model.errorMessage = nil
                model.flow.add(files: files, as: kind)
            } else {
                model.open(files: files)
                if kindBeforeFiles == .brokerage, model.flow.filesKind == .statements {
                    model.flow.setFilesKind(.brokerage)
                }
            }
        }
        report(failures)
    }

    /// The files' bytes, and why the others couldn't be read.
    private func read(_ urls: [URL]) async -> (files: [(name: String, data: Data)],
                                               failures: [(name: String, message: String)]) {
        var files: [(name: String, data: Data)] = []
        var failures: [(name: String, message: String)] = []
        for url in urls {
            do {
                let data = try await ImportFileReader.read(url)
                files.append((url.lastPathComponent, data))
            } catch {
                failures.append((url.lastPathComponent, error.localizedDescription))
            }
        }
        return (files, failures)
    }

    private func report(_ failures: [(name: String, message: String)]) {
        guard !failures.isEmpty else { return }
        model.errorMessage = (failures.count == 1 ? "A file couldn't be opened. " : "Some files couldn't be opened. ")
            + failures.map { "\($0.name): \($0.message)" }.joined(separator: " ")
    }
}

/// The screen's title: on iPhone the step's name, large; on the Mac and
/// iPad "Import", with what's open as the Mac window's subtitle.
private struct ImportTitle: ViewModifier {
    let flow: ImportFlow
    let isCompact: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        if isCompact {
            content
                .navigationTitle(flow.step == .done ? "" : flow.step.title)
                .navigationBarTitleDisplayMode(.large)
                .navigationBarBackButtonHidden()
        } else {
            content
                .navigationTitle("Import")
        }
        #else
        content
            .navigationTitle("Import")
            .personalNavigationSubtitle(flow.step == .done ? "" : flow.displayName ?? "")
        #endif
    }
}

/// The current step's page.
struct ImportStepContent: View {
    let model: ImportController
    let isCompact: Bool
    /// Shows the file importer, which adds files.
    let chooseFile: () -> Void
    /// Adds the files dropped on the Files step.
    let openFiles: ([URL]) -> Void
    /// What the files are before any is read: the Files step's switch.
    var kindBeforeFiles: Binding<ImportFilesKind> = .constant(.statements)

    var body: some View {
        switch model.flow.step {
        case .file:
            ImportFileStep(model: model, isCompact: isCompact, chooseFile: chooseFile, addFiles: openFiles,
                           kindBeforeFiles: kindBeforeFiles)
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

/// The steps along the top, as a capsule: the current one on a raised
/// chip, done ones with a check. Tap a step to go back to it (or forward,
/// once a file is read). Done isn't one of them.
struct ImportStepBar: View {
    let model: ImportController
    /// What the files are before any is read, which says the steps.
    var kindBeforeFiles: ImportFilesKind = .statements

    var body: some View {
        let flow = model.flow
        HStack(spacing: 0) {
            ForEach(Array(flow.barSteps(beforeFiles: kindBeforeFiles).enumerated()), id: \.element) { index, step in
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
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.border.opacity(0.6)))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Steps")
    }

    private func progress(of step: ImportStep, current: ImportStep) -> ImportStepLabel.Progress {
        if step == current { return .current }
        return step < current ? .done : .upcoming
    }
}

/// One step: its number (a check once done) and its name; the current one
/// on a raised chip.
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
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(progress == .upcoming ? Color.clear : Palette.accent)
                Circle()
                    .strokeBorder(progress == .upcoming ? Palette.mutedInk : Palette.accent, lineWidth: 1)
                if progress == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white)
                } else {
                    Text(verbatim: "\(number)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(progress == .current ? Color.white : Palette.secondaryInk)
                }
            }
            .frame(width: 16, height: 16)
            Text(title)
                .font(Self.titleFont.weight(progress == .current ? .semibold : .regular))
                .foregroundStyle(progress == .upcoming ? Palette.secondaryInk : Palette.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Metrics.xs)
        .background {
            if progress == .current {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Palette.card)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Step \(number), \(title)"))
        .accessibilityValue(Text(progress == .current ? "Current" : progress == .done ? "Done" : ""))
    }

    /// 13 pt on the Mac, as its toolbar's text.
    private static var titleFont: Font {
        #if os(macOS)
        .body
        #else
        .subheadline
        #endif
    }
}

// MARK: - The bar at the bottom

/// The bar at the bottom. Mac and iPad: why Continue waits, with a warning
/// sign, at the leading edge; then *Cancel* on the first step or *Back*,
/// and *Continue* (*Import* on Review). iPhone: only Review's *Import*,
/// across the width; the navigation bar has the rest. None on Done.
struct ImportBottomBar: View {
    let model: ImportController
    var isCompact = false
    /// *Cancel*: closes a sheet, starts the page over.
    var cancel: (() -> Void)?

    @Environment(LibraryStore.self) private var library

    var body: some View {
        let flow = model.flow
        if flow.step == .done {
            EmptyView()
        } else if isCompact {
            if flow.step == .preview {
                importButton(flow)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Metrics.l)
                    .padding(.vertical, Metrics.m)
                    .background(Palette.page)
            }
        } else {
            HStack(spacing: Metrics.m) {
                leading(flow)
                Spacer(minLength: Metrics.s)
                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                if flow.previousStep != nil {
                    Button("Back") {
                        model.flow.goBack()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isWorking)
                } else {
                    Button("Cancel") {
                        if let cancel { cancel() } else { model.startOver() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isWorking)
                }
                if flow.step == .preview {
                    importButton(flow)
                } else {
                    Button("Continue") {
                        model.flow.goForward()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(flow.nextStep == nil)
                }
            }
            .padding(.horizontal, Metrics.xl)
            .padding(.vertical, Metrics.m)
            .frame(minHeight: 60)
            .background(.bar)
        }
    }

    /// Why Continue waits, in the warning color; on Income, how lines
    /// count until they're answered.
    @ViewBuilder
    private func leading(_ flow: ImportFlow) -> some View {
        if let hint = flow.continueHint {
            Label {
                Text(hint)
                    .privacySensitiveInFeedback(flow.isBatch)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(Palette.warning)
            .lineLimit(2)
        } else if flow.step == .classify, flow.layout == .statement {
            Text(ImportFlow.incomeNote)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(2)
        }
    }

    private func importButton(_ flow: ImportFlow) -> some View {
        Button {
            Task { await model.runImport(in: library) }
        } label: {
            Text("Import")
                .fontWeight(.semibold)
                .frame(maxWidth: isCompact ? .infinity : nil)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!flow.blockers.isEmpty || model.isWorking || !library.canEdit)
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

#Preview("Import · files") {
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

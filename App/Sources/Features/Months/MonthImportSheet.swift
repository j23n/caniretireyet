import Importer
import Model
import SwiftUI
import UniformTypeIdentifiers

/// *Import CSV…* for one account's month (UI.md, "Your months"): the bank's
/// CSV, read as a statement of that account through the month's check-in.
/// It says how the file is read, with *Change How It's Read…* (the
/// import's reading sheet), asks for the balance before the first line when
/// the file has no balances, and imports. The lines are then checked on the
/// month's lines screen: *Continue to the Lines* runs `continueToLines`.
struct MonthImportSheet: View {
    let route: MonthRoute
    /// Opens the month's lines after the import, when the sheet isn't
    /// shown from them.
    var continueToLines: (() -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var model: ImportController?
    @State private var choosesFile = false
    @State private var showsReading = false
    @State private var openingText = ""

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import CSV")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(model?.receipt == nil ? "Cancel" : "Done") { dismiss() }
                            .disabled(model?.isWorking == true)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if let model, model.receipt == nil {
                            Button("Import") { run(model) }
                                .disabled(!model.flow.blockers.isEmpty || model.isWorking || !library.canEdit)
                        }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
        .fileImporter(isPresented: $choosesFile, allowedContentTypes: ImportFileReader.contentTypes) { result in
            if case .success(let url) = result { open(url) }
        }
        .sheet(isPresented: $showsReading) {
            if let model { ImportReadingSheet(model: model) }
        }
        .onChange(of: library.revision) { _, _ in
            if model?.receipt == nil { model?.libraryChanged(library.library) }
        }
    }

    private var accountName: String {
        library.library.accounts[route.account]?.name ?? route.account.rawValue
    }

    @ViewBuilder
    private var content: some View {
        if let model {
            if model.receipt != nil {
                done
            } else {
                reading(model)
            }
        } else {
            VStack(spacing: Metrics.l) {
                Text("Export the statement from your bank's website as a CSV, covering \(monthName).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.secondaryInk)
                    .privacySensitiveInFeedback()
                Button("Choose a CSV File…") { choosesFile = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!library.canEdit)
            }
            .padding(Metrics.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var monthName: String {
        "\(accountName)'s \(MonthText.title(route.through, locale: locale))"
    }

    private func reading(_ model: ImportController) -> some View {
        Form {
            Section {
                LabeledContent("File") {
                    Text(model.flow.displayName ?? "")
                        .privacySensitiveInFeedback()
                }
                LabeledContent("Account") {
                    Text(accountName)
                        .privacySensitiveInFeedback()
                }
                let status = model.flow.readingStatus()
                Label {
                    Text(status.text)
                } icon: {
                    Image(systemName: status.isProblem ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                }
                .foregroundStyle(status.isProblem ? Palette.warning : Palette.positive)
                .privacySensitiveInFeedback()
                Button("Change How It's Read…") { showsReading = true }
                Button("Choose Another File…") { choosesFile = true }
            }
            if let problem = model.flow.problem {
                Section {
                    Text(problem)
                        .foregroundStyle(Palette.warning)
                        .privacySensitiveInFeedback()
                }
            }
            if model.flow.needsOpeningBalance {
                Section {
                    TextField("Balance before the first line", text: $openingText)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { setOpening(model) }
                        #if os(iOS)
                        .numberKeyboard(.numbersAndPunctuation)
                        #endif
                    Button("Use") { setOpening(model) }
                } footer: {
                    Text("The file has no balances. Give the balance before its first line, as the statement "
                        + "shows it.")
                }
            }
            let blockers = model.flow.blockers.filter { !$0.hasPrefix("Give the balance") }
            if !blockers.isEmpty {
                Section {
                    ForEach(blockers, id: \.self) { reason in
                        Text(reason)
                            .foregroundStyle(Palette.secondaryInk)
                            .privacySensitiveInFeedback()
                    }
                }
            }
            if let message = model.errorMessage {
                Section {
                    Text(message)
                        .foregroundStyle(Palette.critical)
                        .privacySensitiveInFeedback()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var done: some View {
        VStack(spacing: Metrics.l) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(Palette.good)
                .accessibilityHidden(true)
            Text("The statement's lines are in \(monthName). Check what each one is, and the month is done.")
                .multilineTextAlignment(.center)
                .privacySensitiveInFeedback()
            if let continueToLines {
                Button("Continue to the Lines") {
                    dismiss()
                    continueToLines()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Metrics.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    /// Reads the file as a statement of the month's account.
    private func open(_ url: URL) {
        let route = self.route
        let library = self.library.library
        Task {
            let model = ImportController(library: library, checkIn: route.through)
            do {
                let data = try await ImportFileReader.read(url)
                let file = (name: url.lastPathComponent, data: data)
                model.flow.open(statements: [file])
                if let id = model.flow.batch?.files.first?.id {
                    model.flow.setBatchAccount(route.account, forFile: id)
                }
            } catch {
                model.openFailed(fileName: url.lastPathComponent, message: LibraryStore.describe(error))
            }
            self.model = model
        }
    }

    private func setOpening(_ model: ImportController) {
        guard let id = model.flow.batch?.files.first?.id else { return }
        switch AmountInput.parse(openingText, locale: locale) {
        case .empty: model.flow.setStatementOpeningBalance(nil, forFile: id)
        case .value(let value): model.flow.setStatementOpeningBalance(value, forFile: id)
        case .unreadable: break
        }
    }

    private func run(_ model: ImportController) {
        Task { await model.runImport(in: library) }
    }
}

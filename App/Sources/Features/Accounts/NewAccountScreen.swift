import Model
import SwiftUI
import Tracker

/// Adds an account (UI.md, "Add account"), as a sheet:
///
/// 1. Pick a kind from a grid of icons.
/// 2. Name, institution, currency, country and opening date. The opening
///    date is today by default; set to when the account was opened, it
///    leaves room to add the account's history.
/// 3. The positions (choose or create instruments) or the balance on the
///    opening date, which becomes the first valuation. A brokerage, crypto
///    or metals account chooses how it's tracked: its trade history (the
///    default: the positions become opening trades) or monthly snapshots.
/// 4. Whether it counts in net worth and plans, and from what age plans can
///    draw on it (a pension fund from 65 by default).
///
/// ⌘N, the Accounts toolbar and onboarding present it in a NavigationStack.
struct NewAccountScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var form = AccountForm(residence: nil, currency: .eur, today: .today())
    @State private var opening = AccountOpeningForm()
    /// The fields as the sheet opened with them, to tell whether anything was typed.
    @State private var initialForm: AccountForm?
    @State private var showsProblems = false
    @State private var showsNewInstrument = false
    @State private var errorMessage: String?

    init() {}

    var body: some View {
        Form {
            Section {
                AccountKindGrid(selection: $form.chosenKind)
            } header: {
                Text("Kind")
            }
            AccountDetailsFields(form: $form, showsKindPicker: false)
            openingSection
            AccountPlanFields(form: $form)
            if showsProblems {
                AccountsProblemsSection(problems: problems)
            }
            AccountsErrorSection(message: errorMessage)
        }
        .formStyle(.grouped)
        .navigationTitle("New Account")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { add() }
                    .disabled(form.trimmedName.isEmpty || !library.canEdit)
            }
        }
        .onAppear(perform: load)
        .interactiveDismissDisabled(hasUnsavedChanges)
        .sheet(isPresented: $showsNewInstrument) {
            NavigationStack {
                InstrumentEditor(instrumentID: nil, currency: form.currency, isSheet: true) { id in
                    opening.addPosition(id)
                }
            }
            #if os(macOS)
            .frame(minWidth: 460, idealWidth: 520, minHeight: 480, idealHeight: 620)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 520, idealHeight: 720)
        #endif
    }

    // MARK: Opening balance or positions

    @ViewBuilder
    private var openingSection: some View {
        let symbol = AmountFormat.symbol(for: form.currency, locale: locale)
        if form.offersTracking {
            Section {
                Picker("Track", selection: $form.tracking) {
                    Text("Trade history").tag(ValuationMode.trades)
                    Text("Monthly snapshots").tag(ValuationMode.holdings)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Track")
            } footer: {
                Text(verbatim: AccountForm.trackingExplanation(form.tracking))
            }
        }
        if form.holdsPositions {
            Section {
                ForEach(opening.positions) { position in
                    Picker("Instrument", selection: $opening[position: position.id].instrument) {
                        Text("Choose…").tag(InstrumentID?.none)
                        ForEach(instruments) { instrument in
                            Text(instrument.name).tag(Optional(instrument.id))
                        }
                    }
                    AccountsNumberField(title: "Quantity", text: $opening[position: position.id].quantity, prompt: "0",
                                        suffix: unit(of: position.instrument), allowsNegative: false)
                    AccountsNumberField(title: "Paid in total", text: $opening[position: position.id].cost,
                                        prompt: "Optional", suffix: symbol, allowsNegative: false)
                    Button("Remove This Position", role: .destructive) {
                        opening.removePosition(id: position.id)
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    opening.addPosition()
                } label: {
                    Label("Add Position", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                Button {
                    showsNewInstrument = true
                } label: {
                    Label("New Instrument…", systemImage: AppSymbol.instruments)
                }
                .buttonStyle(.borderless)
                AccountsNumberField(title: "Cash", text: $opening.cash, prompt: "0", suffix: symbol)
            } header: {
                Text(form.recordsTrades ? "Opening positions" : "Positions")
            } footer: {
                if form.recordsTrades {
                    Text(verbatim: AccountOpeningForm.openingTradesFooter(opened: form.opened, today: .today(),
                                                                          locale: locale))
                } else {
                    Text(verbatim: AccountOpeningForm.positionsFooter(opened: form.opened, today: .today(),
                                                                      locale: locale))
                }
            }
        } else {
            Section {
                AccountsNumberField(title: form.kind.isLiability ? "Owed" : "Balance", text: $opening.balance,
                                    prompt: "0", suffix: symbol)
            } header: {
                Text("Opening balance")
            } footer: {
                Text(verbatim: AccountOpeningForm.balanceFooter(opened: form.opened, today: .today(),
                                                                isLiability: form.kind.isLiability, locale: locale))
            }
        }
    }

    private var instruments: [Instrument] {
        library.library.instruments.values.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }

    private func unit(of instrument: InstrumentID?) -> String? {
        QuantityFormat.unit(of: instrument.flatMap { library.library.instruments[$0] })
    }

    private var problems: [String] {
        form.problems(locale: locale) + opening.problems(holdsPositions: form.holdsPositions, locale: locale)
    }

    /// Whether anything was typed or chosen, so swiping the sheet down
    /// doesn't lose it: only Cancel does.
    private var hasUnsavedChanges: Bool {
        guard let initialForm else { return false }
        return form != initialForm || opening != AccountOpeningForm()
    }

    // MARK: Actions

    private func load() {
        guard initialForm == nil else { return }
        form = AccountForm(residence: library.settings.taxResidence, currency: library.baseCurrency, today: .today())
        initialForm = form
    }

    private func add() {
        guard problems.isEmpty else {
            showsProblems = true
            return
        }
        let account = form.account(id: library.newAccountID(for: form.trimmedName), locale: locale)
        let valuation = opening.valuation(for: account, in: library.library, locale: locale)
        let trades = opening.openingTrades(for: account, locale: locale)
        do {
            try library.update { library in
                library.accounts[account.id] = account
                if let valuation { library.upsert(valuation) }
                for trade in trades { library.upsert(trade) }
            }
            dismiss()
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}

// MARK: - Fields shared with editing

/// The grid of account kinds (step 1 of adding an account).
private struct AccountKindGrid: View {
    @Binding var selection: AccountKind

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: Metrics.s)], spacing: Metrics.s) {
            ForEach(AccountKind.knownValues, id: \.self) { kind in
                Button {
                    selection = kind
                } label: {
                    tile(for: kind, isSelected: kind == selection)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.displayName)
                .accessibilityAddTraits(kind == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, Metrics.xs)
    }

    private func tile(for kind: AccountKind, isSelected: Bool) -> some View {
        VStack(spacing: Metrics.xs) {
            Image(systemName: kind.systemImage)
                .font(.title3)
            Text(kind.displayName)
                .font(.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isSelected ? Palette.accent : Palette.ink)
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(Metrics.xs)
        .background(isSelected ? Palette.accent.opacity(0.12) : Palette.page,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Palette.accent : Palette.border, lineWidth: isSelected ? 1.5 : 1)
        }
        .contentShape(Rectangle())
    }
}

/// Name, institution, currency, country and opening date (and the kind,
/// when editing).
struct AccountDetailsFields: View {
    @Binding var form: AccountForm
    var showsKindPicker: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        Section {
            if showsKindPicker {
                Picker("Kind", selection: $form.chosenKind) {
                    ForEach(AccountKind.knownValues.including(form.kind), id: \.self) { kind in
                        Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                    }
                }
            }
            AccountsTextField(title: "Name", text: $form.name, prompt: "e.g. Conto Fineco")
            AccountsTextField(title: "Institution", text: $form.institution, prompt: "Bank or broker")
            Picker("Currency", selection: $form.currency) {
                ForEach(CurrencyChoices.common.including(form.currency), id: \.self) { code in
                    Text(CurrencyChoices.name(of: code, locale: locale)).tag(code)
                }
            }
            .disabled(form.locksCurrency)
            Picker("Country", selection: $form.country) {
                Text("None").tag(CountryCode?.none)
                ForEach(CountryChoices.common.including(form.country), id: \.self) { code in
                    Text(CountryChoices.name(of: code, locale: locale)).tag(Optional(code))
                }
            }
            DatePicker("Opened", selection: $form.openedDate, displayedComponents: .date)
        } header: {
            Text("Details")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        if form.isNew {
            return "Set it to when you opened the account, to add its history. The country is the institution's."
        }
        let currency = form.locksCurrency
            ? " The currency can't change: the account's values and trades are in \(form.currency.rawValue)." : ""
        return "The account counts from the day it opens. The country is the institution's." + currency
    }
}

/// Whether it counts in net worth and plans, from what age plans can draw
/// on it, and (for balance accounts) the asset mix.
struct AccountPlanFields: View {
    @Binding var form: AccountForm

    var body: some View {
        if form.kind.recordsMoneyInOut {
            Section {
                Toggle("Track money in and out", isOn: $form.tracksMoneyInOut)
            } footer: {
                Text("Type what came in and went out at each check-in, to see what you spend. Leave out money "
                    + "moved between your own accounts, except credit card payments.")
            }
        }
        Section {
            Toggle("Include in net worth", isOn: $form.includedInNetWorth)
            Toggle("Include in plans", isOn: $form.chosenPlanInclusion)
            if form.includedInPlan && !form.kind.isLiability {
                Toggle("Available only from an age", isOn: $form.chosenIsLocked)
                if form.chosenIsLocked {
                    Stepper("Available from \(form.chosenAvailableFromAge)", value: $form.chosenAvailableFromAge,
                            in: 18...90)
                }
            }
        } header: {
            Text("Plans")
        } footer: {
            Text("Plans usually leave out your home and its mortgage. Money available only from an age, such as a "
                + "pension fund, can't pay for the years before it.")
        }
        if form.takesAssetMix {
            Section {
                AccountsAssetMixFields(mix: $form.assetMix)
            } header: {
                Text("Asset mix")
            } footer: {
                Text(mixFooter)
            }
        }
    }

    private var mixFooter: String {
        if form.holdsPositions && form.balanceValueCount > 0 {
            let values = form.balanceValueCount == 1 ? "1 value" : "\(form.balanceValueCount) values"
            return "For the \(values) recorded as a single balance (positions follow their instruments), "
                + "e.g. 100% equity. Leave empty for \"other\"."
        }
        if let mix = form.kind.defaultAssetClasses, let assetClass = mix.assetClasses.first {
            return "Leave empty to count it as \(BreakdownKey.assetClass(assetClass).description.lowercased()). "
                + "Percentages add up to 100."
        }
        return "What it's invested in, e.g. a pension fund's 60% equity and 40% bonds. Leave empty for \"other\"."
    }
}

#Preview("New account") {
    NavigationStack {
        NewAccountScreen()
    }
    .previewEnvironment()
}

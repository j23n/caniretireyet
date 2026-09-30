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
///    opening date, which becomes the first valuation.
/// 4. The tax wrapper, pre-selected from the kind and your residence (a
///    pension fund in Italy is `it.pensionFund`), and whether it counts in
///    net worth and plans.
///
/// ⌘N, the Accounts toolbar and onboarding present it in a NavigationStack.
struct NewAccountScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var form = AccountForm(residence: nil, currency: .eur, today: .today())
    @State private var opening = AccountOpeningForm()
    @State private var loaded = false
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
            AccountTaxFields(form: $form)
            if showsProblems {
                AccountsProblemsSection(problems: problems)
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "xmark.octagon")
                        .foregroundStyle(Palette.critical)
                }
            }
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
                Text("Positions")
            } footer: {
                Text(verbatim: AccountOpeningForm.positionsFooter(opened: form.opened, today: .today(), locale: locale))
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
        instrument.flatMap { library.library.instruments[$0] }.map { InstrumentForm.shortName(of: $0.unit) }
    }

    private var problems: [String] {
        form.problems(locale: locale) + opening.problems(holdsPositions: form.holdsPositions, locale: locale)
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        form = AccountForm(residence: library.settings.taxResidence, currency: library.baseCurrency, today: .today())
    }

    private func add() {
        guard problems.isEmpty else {
            showsProblems = true
            return
        }
        let account = form.account(id: library.newAccountID(for: form.trimmedName), locale: locale)
        let valuation = opening.valuation(for: account, in: library.library, locale: locale)
        do {
            try library.update { library in
                library.accounts[account.id] = account
                if let valuation { library.upsert(valuation) }
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
                    ForEach(kinds, id: \.self) { kind in
                        Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                    }
                }
            }
            AccountsTextField(title: "Name", text: $form.name, prompt: "e.g. Conto Fineco")
            AccountsTextField(title: "Institution", text: $form.institution, prompt: "Bank or broker")
            Picker("Currency", selection: $form.currency) {
                ForEach(currencies, id: \.self) { code in
                    Text(CurrencyChoices.name(of: code, locale: locale)).tag(code)
                }
            }
            Picker("Country", selection: $form.country) {
                Text("None").tag(CountryCode?.none)
                ForEach(countries, id: \.self) { code in
                    Text(CountryChoices.name(of: code, locale: locale)).tag(Optional(code))
                }
            }
            DatePicker("Opened", selection: $form.openedDate, displayedComponents: .date)
        } header: {
            Text("Details")
        } footer: {
            Text(form.isNew
                ? "Set it to when you opened the account, to add its history. The country is the institution's."
                : "The account counts from the day it opens. The country is the institution's.")
        }
    }

    private var kinds: [AccountKind] {
        AccountKind.knownValues.contains(form.kind) ? AccountKind.knownValues : [form.kind] + AccountKind.knownValues
    }

    private var currencies: [CurrencyCode] {
        CurrencyChoices.common.contains(form.currency) ? CurrencyChoices.common : [form.currency] + CurrencyChoices.common
    }

    private var countries: [CountryCode] {
        guard let country = form.country, !CountryChoices.common.contains(country) else { return CountryChoices.common }
        return [country] + CountryChoices.common
    }
}

/// The tax wrapper, whether it counts in net worth and plans, and (for
/// balance accounts) the asset mix.
struct AccountTaxFields: View {
    @Binding var form: AccountForm

    var body: some View {
        Section {
            Picker("Tax wrapper", selection: $form.chosenWrapper) {
                Text("None").tag(WrapperID?.none)
                ForEach(wrappers, id: \.self) { wrapper in
                    Text(AccountWrapperDefaults.name(of: wrapper)).tag(Optional(wrapper))
                }
            }
            Toggle("Include in net worth", isOn: $form.includedInNetWorth)
            Toggle("Include in plans", isOn: $form.chosenPlanInclusion)
        } header: {
            Text("Taxes and plans")
        } footer: {
            Text("The wrapper decides how plans tax the account. Plans usually leave out your home and its mortgage.")
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

    private var wrappers: [WrapperID] {
        guard let wrapper = form.wrapper, !AccountWrapperDefaults.choices.contains(wrapper) else {
            return AccountWrapperDefaults.choices
        }
        return [wrapper] + AccountWrapperDefaults.choices
    }

    private var mixFooter: String {
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

import Model
import SwiftUI
import Tracker

/// Adds an account (UI.md, "Add account"), as a sheet:
///
/// 1. Pick a kind from a grid of icons.
/// 2. Name, institution, currency, country and opening date. The opening
///    date is today by default; set to when the account was opened, it
///    leaves room to add the account's history.
/// 3. Whether it counts in net worth and plans, and from what age plans can
///    draw on it (a pension fund from 65 by default).
///
/// It starts with no values: they come from importing its files (a bank's
/// statement, a broker's export, or a spreadsheet you keep for it).
///
/// ⌘N and the Accounts toolbar present it in a NavigationStack; first
/// launch's accounts step pushes it on its own stack, which *Cancel* and
/// *Add* go back to.
struct NewAccountScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var form = AccountForm(residence: nil, currency: .eur, today: .today())
    /// The fields as the sheet opened with them, to tell whether anything was typed.
    @State private var initialForm: AccountForm?
    @State private var showsProblems = false
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
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 560, minHeight: 520, idealHeight: 720)
        #endif
    }

    private var problems: [String] {
        form.problems(locale: locale)
    }

    /// Whether anything was typed or chosen, so swiping the sheet down
    /// doesn't lose it: only Cancel does.
    private var hasUnsavedChanges: Bool {
        guard let initialForm else { return false }
        return form != initialForm
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
        do {
            try library.update { library in
                library.accounts[account.id] = account
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
                .personalControl()
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
        Section {
            Toggle("Include in net worth", isOn: $form.chosenNetWorthInclusion)
            Toggle("Include in plans", isOn: $form.chosenPlanInclusion)
            if form.includedInPlan && !form.kind.isLiability {
                Toggle("Available only from an age", isOn: $form.chosenIsLocked)
                if form.chosenIsLocked {
                    Stepper("Available from \(form.chosenAvailableFromAge)", value: $form.chosenAvailableFromAge,
                            in: 18...90)
                        .privacySensitiveInFeedback()
                }
            }
        } header: {
            Text("Plans")
        } footer: {
            Text(plansFooter)
        }
        if form.takesDepreciation {
            Section {
                AccountsNumberField(title: "Loses a year", text: $form.depreciation, prompt: "None", suffix: "%",
                                    allowsNegative: false)
            } header: {
                Text("Loss of value")
            } footer: {
                Text("Between the values you type, its value is estimated from this, and its loss of value counts as "
                    + "spent. The next value you type corrects the estimate.")
            }
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

    private var plansFooter: String {
        if form.kind == .taxPot {
            return "Money you set aside for a tax bill is owed, so net worth and plans leave it out. What you put "
                + "in counts as tax: what came in is after it, and it isn't spent."
        }
        return "Plans usually leave out your home and its mortgage. Money available only from an age, such as a "
            + "pension fund, can't pay for the years before it."
    }

    private var mixFooter: String {
        if form.recordsTrades && form.balanceValueCount > 0 {
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

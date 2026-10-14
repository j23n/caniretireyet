import CloudSync
import Glance
import Model
import SwiftUI

/// First launch (UI.md, "Empty states and first launch"), a short tour:
/// what the app does, where to keep the data (iCloud Drive is
/// recommended), birth date, base currency and country, then take-home pay,
/// spending and the age to retire at (all optional) and the monthly
/// reminder. *Create library* creates the library and a first plan from
/// them (`PlanEditing.starterPlan`). Then accounts, added with
/// `NewAccountScreen` or imported with `ImportScreen`, both pushed on the
/// tour's own stack, or skipped; and last the disclaimer, whose *Start*
/// opens the Overview.
///
/// The root view keeps showing it after the library is created, while
/// `AppNavigation.finishesOnboarding` is set.
struct OnboardingScreen: View {
    /// What the tour pushes on its own stack.
    private enum Destination: Hashable {
        case newAccount
        case importFile
    }

    /// The ages to retire at that can be chosen, as in the plan's editor.
    static let retirementAges = 30...85

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(AppPreferences.self) private var preferences
    @Environment(NoteStore.self) private var notes
    @Environment(\.locale) private var locale

    @State private var step: OnboardingStep = .welcome
    @State private var path: [Destination] = []
    @State private var location: LibraryLocationKind = .iCloud
    @State private var name = ""
    /// The birth date picked; `nil` until one is, so none is made up.
    @State private var birthDate: Date?
    /// The birth-date picker is showing; `birthDate` is set only once a
    /// date is picked in it.
    @State private var addsBirthDate = false
    /// The date the picker shows before one is saved.
    @State private var pickedBirthDate = YouSettings.suggestedBirthDate().dateValue
    /// The device's currency and region to start with; nothing else is assumed.
    @State private var currency = CurrencyCode(Locale.current.currency?.identifier ?? "EUR")
    @State private var residence: CountryCode? = Locale.current.region.map { CountryCode($0.identifier) }
    /// Take-home pay and spending a month, in the base currency; optional.
    @State private var payPerMonth: Decimal?
    @State private var spendingPerMonth: Decimal?
    /// The age to retire at; `nil`: as early as possible.
    @State private var retirementAge: Int?
    @State private var remindsMonthly = true
    @State private var isCreating = false
    @State private var error: String?

    init() {}

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.xl) {
                    switch step {
                    case .welcome: welcome
                    case .location: locationStep
                    case .you: youStep
                    case .money: moneyStep
                    case .accounts: accountsStep
                    case .disclaimer: disclaimerStep
                    }
                    if let error {
                        StatusBanner(.error, "Couldn't create the library", message: error, personal: .message)
                    }
                }
                .padding(Metrics.xl)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.page)
            .safeAreaInset(edge: .bottom) { buttons }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .newAccount:
                    // Cancel and Add go back to the accounts step.
                    NewAccountScreen()
                        .navigationBarBackButtonHidden()
                case .importFile:
                    ImportScreen(close: { path = [] })
                        .navigationBarBackButtonHidden()
                }
            }
        }
        .onAppear {
            if !library.isICloudAvailable { location = .local }
            if let requested = navigation.requestedOnboardingStep {
                step = requested
                navigation.requestedOnboardingStep = nil
            } else if navigation.finishesOnboarding, library.phase == .ready, !step.comesAfterCreating {
                // Back after the opening screen showed the new library's
                // download: the library exists.
                step = .accounts
            }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text("Can I Retire Yet?")
                .font(.largeTitle.bold())
            Text("See what you own, and when it lets you stop working.")
                .foregroundStyle(Palette.secondaryInk)
            VStack(alignment: .leading, spacing: Metrics.l) {
                OnboardingFeature(
                    title: "A check-in each month", systemImage: AppSymbol.checkIn,
                    detail: "Once a month, record what your accounts are worth. It takes a few minutes, and the app "
                        + "keeps the history.")
                OnboardingFeature(
                    title: "Plans that answer", systemImage: AppSymbol.plan,
                    detail: "A plan says what you earn, spend and expect. It answers the question in the app's name: "
                        + "can I retire yet, and if not, when? The Overview shows your main plan's answer.")
                OnboardingFeature(
                    title: "Files you own", systemImage: "doc.text",
                    detail: "Everything is kept as plain files, in iCloud Drive or on this device. There's no "
                        + "account to create and no server.")
            }
            .onboardingCard()
        }
    }

    private var locationStep: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            Text("Where should your data live?")
                .font(.title2.bold())
            LocationChoice(
                title: "iCloud Drive", systemImage: "icloud",
                detail: "Recommended. Your iPhone and Mac share the same library, and you can see the files in the "
                    + "Can I Retire Yet folder.",
                isSelected: location == .iCloud, isEnabled: library.isICloudAvailable
            ) { location = .iCloud }
            LocationChoice(
                title: "This device", systemImage: "internaldrive",
                detail: "Kept only here. You can move it to iCloud Drive later in Settings.",
                isSelected: location == .local, isEnabled: true
            ) { location = .local }
            if !library.isICloudAvailable {
                Text("iCloud Drive is off. To use it, sign in to iCloud and turn on iCloud Drive in Settings.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    private var youStep: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            Text("About you")
                .font(.title2.bold())
            Text("Plans use your birth date for ages, and the base currency for totals. The country you live in "
                + "picks the inflation index amounts are adjusted with.")
                .foregroundStyle(Palette.secondaryInk)
            VStack(alignment: .leading, spacing: Metrics.m) {
                TextField("Name (optional)", text: $name)
                    .textFieldStyle(.roundedBorder)
                birthDateRow
                LabeledContent("Base currency") {
                    Picker("Base currency", selection: $currency) {
                        ForEach(CurrencyChoices.common.including(currency), id: \.self) { code in
                            Text(CurrencyChoices.name(of: code, locale: locale)).tag(code)
                        }
                    }
                    .labelsHidden()
                }
                LabeledContent("Country") {
                    Picker("Country", selection: $residence) {
                        Text("Not set").tag(CountryCode?.none)
                        ForEach(CountryChoices.common.including(residence), id: \.self) { code in
                            Text(CountryChoices.name(of: code, locale: locale)).tag(Optional(code))
                        }
                    }
                    .labelsHidden()
                }
            }
            .onboardingCard()
        }
    }

    /// "Birth date: Add" until it's tapped, then the picker, which shows
    /// `YouSettings.suggestedBirthDate()` but saves nothing until a date is
    /// picked or *Use This Date* is tapped; *Remove* unsets it again.
    /// Without one the library is still created; the plan asks for it on
    /// its *You* card.
    @ViewBuilder private var birthDateRow: some View {
        if birthDate != nil || addsBirthDate {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                DatePicker("Birth date", selection: birthDateBinding, in: ...Date(), displayedComponents: .date)
                    .personalControl()
                if birthDate == nil {
                    HStack {
                        Text("Not set yet: pick a date, or use the one shown.")
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                        Spacer()
                        Button("Use This Date") { birthDate = pickedBirthDate }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Button("Remove Birth Date") {
                        birthDate = nil
                        addsBirthDate = false
                    }
                    .font(.footnote)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                LabeledContent("Birth date") {
                    Button("Add Birth Date") { addsBirthDate = true }
                        .buttonStyle(.bordered)
                }
                Text("Plans need it for your age. You can add it later too.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    private var birthDateBinding: Binding<Date> {
        Binding(get: { birthDate ?? pickedBirthDate }, set: { date in
            pickedBirthDate = date
            birthDate = date
        })
    }

    private var moneyStep: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            Text("Your money and your plan")
                .font(.title2.bold())
            Text(moneyIntro)
                .foregroundStyle(Palette.secondaryInk)
            VStack(alignment: .leading, spacing: Metrics.m) {
                PlanNumberRow("Take-home pay", value: $payPerMonth, unit: "/month")
                PlanNumberRow("Spending", value: $spendingPerMonth, unit: "/month")
                if hasNegativeAmount {
                    PlanIssueLine(message: "Pay and spending can't be negative.", isError: true)
                }
                Divider()
                retirementRow
            }
            .onboardingCard()
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Toggle("Remind me to check in each month", isOn: $remindsMonthly)
                Text("On the last day of the month, with where you stand, and once a year your year in review. "
                     + "On this device. Change it in Settings.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .onboardingCard()
        }
    }

    /// "Retire at: Add Age" until it's tapped, then a stepper; *Retire As
    /// Early As Possible* goes back to none. The starter plan retires at
    /// the age, else as early as possible. It shows without a birth date
    /// too, which the plan asks for on its *You* card.
    @ViewBuilder private var retirementRow: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            if let retirementAge {
                Stepper("Retire at \(retirementAge)", value: retirementAgeBinding, in: Self.retirementAges)
                Button("Retire As Early As Possible") { self.retirementAge = nil }
                    .font(.footnote)
            } else {
                LabeledContent("Retire at") {
                    Button("Add Age") { retirementAge = suggestedRetirementAge }
                        .buttonStyle(.bordered)
                }
                Text("As early as possible, until you choose an age.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
            if birthDate == nil {
                Text("Plans need your birth date to use it.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }

    private var retirementAgeBinding: Binding<Int> {
        Binding(get: { retirementAge ?? suggestedRetirementAge }, set: { retirementAge = $0 })
    }

    /// The age *Add Age* starts from: 60, or next year's age for someone 60
    /// or older, within ``retirementAges``.
    private var suggestedRetirementAge: Int {
        let age = birthDate.flatMap { Calendar.current.dateComponents([.year], from: $0, to: Date()).year } ?? 0
        return min(max(60, age + 1), Self.retirementAges.upperBound)
    }

    /// Outside the euro a new library has no exchange rates to convert the
    /// default spending with, so without spending there's no first plan
    /// (``PlanEditing/starterPlan(id:name:library:asOf:payPerMonth:spendingPerMonth:retirementAge:)``).
    private var moneyIntro: String {
        let intro = "Optional. Your first plan starts from these, in \(currency.rawValue) after tax, so it can answer "
            + "as soon as your accounts are in. You can change them in the plan any time."
        return currency == .eur ? intro : intro + " Without spending, there's no first plan yet."
    }

    /// A negative amount is never used, so *Create library* waits until it's fixed.
    private var hasNegativeAmount: Bool {
        (payPerMonth ?? 0) < 0 || (spendingPerMonth ?? 0) < 0
    }

    private var accountsStep: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            Text("Your accounts")
                .font(.title2.bold())
            Text("Add what you have: current and savings accounts, investments, pension funds, property and debts. "
                + "Each check-in records what they're worth, and plans draw on them.")
                .foregroundStyle(Palette.secondaryInk)
            if !accounts.isEmpty {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    ForEach(accounts) { account in
                        Label(account.name, systemImage: account.kind.systemImage)
                            .privacySensitiveInFeedback()
                    }
                }
                .onboardingCard()
            }
            Button {
                path.append(.newAccount)
            } label: {
                Label("Add an Account", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!library.canEdit)
            Button {
                path.append(.importFile)
            } label: {
                Label("Import a Spreadsheet", systemImage: AppSymbol.importData)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(!library.canEdit)
            Text("Optional. You can add accounts and import your history any time later.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
        }
    }

    /// The library's open accounts, by name: those added here, imported, or
    /// in a library that was already in iCloud Drive.
    private var accounts: [Account] {
        library.library.accounts.values.filter { !$0.isClosed }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var disclaimerStep: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            Image(systemName: "info.circle")
                .font(.system(size: 44))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text("Before you start")
                .font(.title2.bold())
            Text(AboutText.about)
            Text(Self.nextSteps(planName: library.mainPlan?.name,
                                hasBirthDate: library.settings.person?.birthDate != nil))
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback()
        }
    }

    /// Under the disclaimer: the first check-in, and the plan onboarding
    /// created, which answers only once the birth date is set.
    static func nextSteps(planName: String?, hasBirthDate: Bool) -> String {
        let checkIn = "Start with your first check-in, from the Overview: it records what your accounts are worth today."
        guard let planName else { return checkIn + " Then create your first plan." }
        guard hasBirthDate else {
            return checkIn + " Then add your birth date on your plan's You card, so \(planName) can answer."
        }
        return checkIn + " Your plan, \(planName), answers from it."
    }

    private var buttons: some View {
        HStack {
            if let previous = step.previous {
                Button("Back") {
                    withAnimation { step = previous }
                }
                .disabled(isCreating)
            }
            Spacer()
            switch step {
            case .money:
                Button {
                    create()
                } label: {
                    if isCreating {
                        ProgressView()
                    } else {
                        Text("Create library")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating || hasNegativeAmount)
            case .accounts:
                Button(accounts.isEmpty ? "Skip" : "Continue") {
                    withAnimation { step = .disclaimer }
                }
                .buttonStyle(.borderedProminent)
            case .disclaimer:
                Button("Start") { start() }
                    .buttonStyle(.borderedProminent)
            case .welcome, .location, .you:
                Button("Continue") {
                    withAnimation { step = step.next ?? step }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Metrics.l)
        .background(.bar)
    }

    private func create() {
        isCreating = true
        error = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let person = Person(name: trimmed.isEmpty ? nil : trimmed,
                            birthDate: birthDate.map { CalendarDate($0, in: .current) })
        let settings = LibrarySettings(baseCurrency: currency, person: person == Person() ? nil : person,
                                       taxResidence: residence)
        let kind = location
        // Keeps the tour on screen once the library is open, for its last steps.
        navigation.finishesOnboarding = true
        Task {
            defer { isCreating = false }
            do {
                try await library.createLibrary(in: kind, settings: settings)
                createStarterPlan(currency: settings.baseCurrency)
                if remindsMonthly { turnOnReminder() }
                withAnimation { step = .accounts }
            } catch {
                navigation.finishesOnboarding = false
                self.error = LibraryStore.describe(error)
            }
        }
    }

    /// *Start*: leaves the tour for the Overview.
    private func start() {
        navigation.showOverview()
        navigation.finishesOnboarding = false
    }

    /// The first plan, as the main plan, in a library without plans (one
    /// synced from another device keeps its own, also a plan file that
    /// didn't load), and only in the `currency` the amounts were entered
    /// in: a library that appeared in iCloud Drive meanwhile is opened
    /// instead, with its own. None without spending outside the euro
    /// (``PlanEditing/starterPlan(id:name:library:asOf:payPerMonth:spendingPerMonth:retirementAge:)``).
    /// When there's none, or it can't be saved, the Plan screen still
    /// offers to create one.
    private func createStarterPlan(currency: CurrencyCode) {
        let hasUnloadedPlan = library.unloadedFiles.contains { if case .plan = $0 { true } else { false } }
        guard library.canEdit, library.library.plans.isEmpty, !hasUnloadedPlan,
              library.settings.baseCurrency == currency,
              let plan = PlanEditing.starterPlan(
                  id: library.newPlanID(for: PlanEditing.starterPlanName), name: PlanEditing.starterPlanName,
                  library: library.library, asOf: library.asOfDate,
                  payPerMonth: payPerMonth, spendingPerMonth: spendingPerMonth, retirementAge: retirementAge)
        else { return }
        do {
            // One write, so the plan is never saved without becoming the main plan.
            try library.update { edited in
                edited.plans[plan.id] = plan
                if edited.settings.mainPlan == nil { edited.settings.mainPlan = plan.id }
            }
        } catch {
            let message = LibraryStore.describe(error)
            LibraryLog.error("Onboarding: couldn't save the first plan: \(message)")
        }
    }

    /// The monthly note and *Your year* on this device, as Settings turns
    /// them on (UI.md, "Notifications"), unless notes are set already. When
    /// notifications aren't allowed they stay off, so Settings doesn't show
    /// notes that never come.
    private func turnOnReminder() {
        guard !preferences.notes.isAnyOn else { return }
        Task { await notes.apply(.standard) }
    }
}

private extension View {
    /// A card around a group of onboarding fields.
    func onboardingCard() -> some View {
        padding(Metrics.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            }
    }
}

/// One of the main features on the welcome: an icon, a title and a line.
private struct OnboardingFeature: View {
    let title: String
    let systemImage: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.m) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Palette.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(title).font(.headline).foregroundStyle(Palette.ink)
                Text(detail).font(.subheadline).foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One choice of where to keep the library.
private struct LocationChoice: View {
    let title: String
    let systemImage: String
    let detail: String
    let isSelected: Bool
    let isEnabled: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: Metrics.m) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Text(title).font(.headline).foregroundStyle(Palette.ink)
                    Text(detail).font(.subheadline).foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Palette.accent : Palette.mutedInk)
                    .accessibilityHidden(true)
            }
            .padding(Metrics.l)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accent : Palette.border, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Onboarding") {
    OnboardingScreen()
        .previewEnvironment(PreviewLibrary.empty)
}

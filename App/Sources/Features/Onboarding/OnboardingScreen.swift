import CloudSync
import Model
import SwiftUI

/// First launch (UI.md, "Empty states and first launch"): welcome, where to
/// keep the data (iCloud Drive is recommended), then birth date, base
/// currency and country, then take-home pay and spending (optional) and the
/// monthly reminder. Creating the library also creates a first plan from
/// them (`PlanEditing.starterPlan`). What to do next (import, add
/// accounts, see the plan) follows in `WelcomeNextStepsView`.
struct OnboardingScreen: View {
    private enum Step: Int, CaseIterable {
        case welcome
        case location
        case you
        case money
    }

    /// The name of the plan onboarding creates.
    static let starterPlanName = "Base case"

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.locale) private var locale

    @State private var step: Step = .welcome
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
    @State private var remindsMonthly = true
    @State private var isCreating = false
    @State private var error: String?

    init() {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.xl) {
                    switch step {
                    case .welcome: welcome
                    case .location: locationStep
                    case .you: youStep
                    case .money: moneyStep
                    }
                    if let error {
                        StatusBanner(.error, "Couldn't create the library", message: error)
                    }
                }
                .padding(Metrics.xl)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.page)
            .safeAreaInset(edge: .bottom) { buttons }
        }
        .onAppear {
            if !library.isICloudAvailable { location = .local }
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
            Text("Once a month, record what your accounts are worth. The app keeps the history, and your plans answer the question in its name: can I retire yet, and if not, when?")
                .foregroundStyle(Palette.secondaryInk)
            Text("Everything is kept as plain files that you own. There's no account to create and no server.")
                .foregroundStyle(Palette.secondaryInk)
            Text(AboutText.welcome)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
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
            Text("Your money")
                .font(.title2.bold())
            Text("Optional. Your first plan starts from these, in \(currency.rawValue) after tax, so it can answer "
                + "as soon as your accounts are in. You can change them in the plan any time.")
                .foregroundStyle(Palette.secondaryInk)
            VStack(alignment: .leading, spacing: Metrics.m) {
                PlanNumberRow("Take-home pay", value: $payPerMonth, unit: "/month")
                PlanNumberRow("Spending", value: $spendingPerMonth, unit: "/month")
            }
            .onboardingCard()
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Toggle("Remind me to check in each month", isOn: $remindsMonthly)
                Text("On the last day of the month, on this device. Change it in Settings.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .onboardingCard()
        }
    }

    private var buttons: some View {
        HStack {
            if step != .welcome {
                Button("Back") {
                    withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .welcome }
                }
                .disabled(isCreating)
            }
            Spacer()
            if step == .money {
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
                .disabled(isCreating)
            } else {
                Button("Continue") {
                    withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .money }
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
        Task {
            defer { isCreating = false }
            do {
                try await library.createLibrary(in: kind, settings: settings)
                createStarterPlan(currency: settings.baseCurrency)
                if remindsMonthly { turnOnReminder() }
                navigation.sheet = .welcome
            } catch {
                self.error = LibraryStore.describe(error)
            }
        }
    }

    /// The first plan, as the main plan, in a library without plans (one
    /// synced from another device keeps its own, also a plan file that
    /// didn't load), and only in the `currency` the amounts were entered
    /// in: a library that appeared in iCloud Drive meanwhile is opened
    /// instead, with its own. If it can't be saved, the Plan screen still
    /// offers to create one.
    private func createStarterPlan(currency: CurrencyCode) {
        let hasUnloadedPlan = library.unloadedFiles.contains { if case .plan = $0 { true } else { false } }
        guard library.canEdit, library.library.plans.isEmpty, !hasUnloadedPlan,
              library.settings.baseCurrency == currency else { return }
        let plan = PlanEditing.starterPlan(
            id: library.newPlanID(for: Self.starterPlanName), name: Self.starterPlanName, library: library.library,
            asOf: library.asOfDate, payPerMonth: payPerMonth, spendingPerMonth: spendingPerMonth)
        do {
            try library.save(plan)
            if library.settings.mainPlan == nil { try library.setMainPlan(plan.id) }
        } catch {
            let message = LibraryStore.describe(error)
            LibraryLog.error("Onboarding: couldn't save the first plan: \(message)")
        }
    }

    /// The monthly check-in reminder on this device, as Settings turns it
    /// on, unless one is set already. When notifications aren't allowed,
    /// it's turned off again, so Settings doesn't show one that never comes.
    private func turnOnReminder() {
        guard preferences.reminder == nil else { return }
        let reminder = CheckInReminder.standard
        preferences.reminder = reminder
        #if canImport(UserNotifications)
        Task {
            let scheduled = await ReminderScheduler.apply(reminder)
            if !scheduled { preferences.reminder = nil }
        }
        #endif
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

/// After onboarding: one clear next step, and the plan onboarding created
/// (UI.md, first launch 5).
struct WelcomeNextStepsView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    init() {}

    var body: some View {
        let plan = library.mainPlan
        VStack(alignment: .leading, spacing: Metrics.l) {
            Text("Your library is ready")
                .font(.title2.bold())
            Text(Self.intro(hasPlan: plan != nil))
                .foregroundStyle(Palette.secondaryInk)
            Button {
                dismiss()
                navigation.startImport()
            } label: {
                Label("Import a spreadsheet", systemImage: AppSymbol.importData)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            Button {
                navigation.sheet = .newAccount
            } label: {
                Label("Add accounts", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            if let plan {
                Button {
                    dismiss()
                    navigation.showPlan(plan.id)
                } label: {
                    Label("See your plan, \(plan.name)", systemImage: AppSymbol.plan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(Metrics.xl)
        .navigationTitle("Welcome")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Later") { dismiss() }
            }
        }
    }

    /// The line under the title: what to do next, and the plan when
    /// onboarding created one.
    static func intro(hasPlan: Bool) -> String {
        let accounts = "Bring in your history from a spreadsheet, or add your accounts one by one."
        guard hasPlan else { return accounts + " Then do your first check-in, and create your first plan." }
        return accounts + " Then do your first check-in: your first plan answers from what your accounts are worth."
    }
}

#Preview("Onboarding") {
    OnboardingScreen()
        .previewEnvironment(PreviewLibrary.empty)
}

#Preview("Next steps") {
    NavigationStack {
        WelcomeNextStepsView()
    }
    .previewEnvironment(PreviewLibrary.empty)
}

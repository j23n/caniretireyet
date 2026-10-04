import CloudSync
import Model
import SwiftUI

/// First launch (UI.md, "Empty states and first launch"): welcome, where to
/// keep the data (iCloud Drive is recommended), then birth date, base
/// currency and tax residence, which create the library. What to do next
/// (import, add accounts) follows in `WelcomeNextStepsView`.
struct OnboardingScreen: View {
    private enum Step: Int, CaseIterable {
        case welcome
        case location
        case you
    }

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale

    @State private var step: Step = .welcome
    @State private var location: LibraryLocationKind = .iCloud
    @State private var name = ""
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -35, to: Date()) ?? Date()
    /// The device's currency and region to start with; nothing else is assumed.
    @State private var currency = CurrencyCode(Locale.current.currency?.identifier ?? "EUR")
    @State private var residence: CountryCode? = Locale.current.region.map { CountryCode($0.identifier) }
    @State private var citizenship: CountryCode?
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
            Text("Plans use your birth date for ages, the base currency for totals, and your tax residence as the default for new plans.")
                .foregroundStyle(Palette.secondaryInk)
            VStack(alignment: .leading, spacing: Metrics.m) {
                TextField("Name (optional)", text: $name)
                    .textFieldStyle(.roundedBorder)
                DatePicker("Birth date", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                LabeledContent("Base currency") {
                    Picker("Base currency", selection: $currency) {
                        ForEach(currencyOptions, id: \.self) { code in
                            Text(CurrencyChoices.name(of: code, locale: locale)).tag(code)
                        }
                    }
                    .labelsHidden()
                }
                LabeledContent("Tax residence") {
                    Picker("Tax residence", selection: $residence) {
                        Text("Not set").tag(CountryCode?.none)
                        ForEach(countryOptions(including: residence), id: \.self) { code in
                            Text(CountryChoices.name(of: code, locale: locale)).tag(Optional(code))
                        }
                    }
                    .labelsHidden()
                }
                LabeledContent("Citizenship") {
                    Picker("Citizenship", selection: $citizenship) {
                        Text("Not set").tag(CountryCode?.none)
                        ForEach(countryOptions(including: citizenship), id: \.self) { code in
                            Text(CountryChoices.name(of: code, locale: locale)).tag(Optional(code))
                        }
                    }
                    .labelsHidden()
                }
                Text(YouSettings.citizenshipExplanation)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .padding(Metrics.l)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            }
            if let note = YouSettings.taxRulesNote(for: residence, locale: locale) {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
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
            if step == .you {
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
                    withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .you }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Metrics.l)
        .background(.bar)
    }

    // MARK: Choices

    private var currencyOptions: [CurrencyCode] {
        CurrencyChoices.common.contains(currency) ? CurrencyChoices.common : [currency] + CurrencyChoices.common
    }

    private func countryOptions(including code: CountryCode?) -> [CountryCode] {
        guard let code, !CountryChoices.common.contains(code) else { return CountryChoices.common }
        return [code] + CountryChoices.common
    }

    private func create() {
        isCreating = true
        error = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = LibrarySettings(
            baseCurrency: currency,
            person: Person(name: trimmed.isEmpty ? nil : trimmed, birthDate: CalendarDate(birthDate, in: .current),
                           citizenships: citizenship.map { [$0] } ?? []),
            taxResidence: residence)
        let kind = location
        Task {
            defer { isCreating = false }
            do {
                try await library.createLibrary(in: kind, settings: settings)
                navigation.sheet = .welcome
            } catch {
                self.error = LibraryStore.describe(error)
            }
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

/// After onboarding: one clear next step (UI.md, first launch 4–6).
struct WelcomeNextStepsView: View {
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            Text("Your library is ready")
                .font(.title2.bold())
            Text("Bring in your history from a spreadsheet or ledger journals, or add your accounts one by one. Then do your first check-in, and create your first plan.")
                .foregroundStyle(Palette.secondaryInk)
            Button {
                dismiss()
                navigation.startImport()
            } label: {
                Label("Import a spreadsheet or journals", systemImage: AppSymbol.importData)
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

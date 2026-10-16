import Model
import Planner
import SwiftUI

/// The welcome: the question the app answers, what the tour leads to, and
/// three promises. The calendar page stays blank until the answer fills
/// it in.
struct OnboardingWelcome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            OnboardingCalendarPage(date: nil)
            Text("Can I Retire Yet?")
                .font(.largeTitle.bold())
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text("When could your last Monday at work be?")
                .font(.title3)
                .foregroundStyle(Palette.ink)
            Text("Enter rough amounts for what you have, earn and spend. Your first answer takes about three minutes.")
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Metrics.l) {
                OnboardingRow(title: "Your retirement age", systemImage: AppSymbol.plan,
                              detail: "The earliest age you could retire at, and how likely it is to work across "
                                + "thousands of simulated markets.")
                OnboardingRow(title: "A monthly check-in", systemImage: AppSymbol.checkIn,
                              detail: "Import your statements once a month to see how your answer changes.")
                OnboardingRow(title: "Your data stays with you", systemImage: "doc.text",
                              detail: "Your library is stored as files in iCloud Drive or on this device. There is "
                                + "no account and no server.")
            }
            .onboardingCard()
        }
    }
}

/// About you: the birth date first, since the answer is an age; the
/// country, which sets the currency and names the inflation index; and
/// whether to keep the library in iCloud Drive.
struct OnboardingYouStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Metrics.l) {
            OnboardingTitle("About you",
                            detail: "The answer is an age, so the app needs your birth date.")
            VStack(alignment: .leading, spacing: Metrics.m) {
                birthDateRow
                Divider()
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    LabeledContent("Country") {
                        Picker("Country", selection: countryBinding) {
                            Text("Not set").tag(CountryCode?.none)
                            ForEach(CountryChoices.common.including(model.country), id: \.self) { code in
                                Text(CountryChoices.name(of: code, locale: locale)).tag(Optional(code))
                            }
                        }
                        .labelsHidden()
                    }
                    LabeledContent("Currency") {
                        Picker("Currency", selection: $model.currency) {
                            ForEach(CurrencyChoices.common.including(model.currency), id: \.self) { code in
                                Text(CurrencyChoices.name(of: code, locale: locale)).tag(code)
                            }
                        }
                        .labelsHidden()
                    }
                    Text(OnboardingText.countryLine(country: model.country, currency: model.currency, locale: locale))
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onboardingCard()
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Toggle("Keep in iCloud Drive", isOn: $model.keepsInICloud)
                    .disabled(!library.isICloudAvailable || model.tourRecords != nil)
                Text(model.tourRecords != nil
                     ? "Your library is already created, so this can't change here."
                     : library.isICloudAvailable
                     ? "Your iPhone and Mac use the same library. Turn this off to keep it on this device only."
                     : "iCloud Drive is off, so your library stays on this device. You can move it to iCloud Drive "
                        + "later in Settings.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onboardingCard()
        }
    }

    /// The picker, always there: it shows a suggestion, saved once a date
    /// is picked or *Use This Date* is tapped, so none is made up.
    /// *Continue* waits for one (`OnboardingModel.canContinue`).
    private var birthDateRow: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            DatePicker("Born", selection: birthDateBinding, in: ...Date(), displayedComponents: .date)
                .personalControl()
            if let line = OnboardingText.ageLine(birthDate: model.birthCalendarDate) {
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .privacySensitiveInFeedback()
            } else {
                HStack {
                    Text("Pick your birth date to continue, or use the one shown.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Use This Date") { model.birthDate = model.pickedBirthDate }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private var birthDateBinding: Binding<Date> {
        Binding(get: { model.birthDate ?? model.pickedBirthDate }, set: { date in
            model.pickedBirthDate = date
            model.birthDate = date
        })
    }

    private var countryBinding: Binding<CountryCode?> {
        Binding(get: { model.country }, set: { model.choose(country: $0) })
    }
}

/// Your money: what you have today, in four plain buckets (the home with
/// what's still owed on it) that become the starting estimates, and pay and
/// spending a month, with what you save as you type. Once you've stopped
/// working there's no pay: spending is what you live on now.
struct OnboardingMoneyStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Metrics.l) {
            OnboardingTitle("Your money",
                            detail: "Rough amounts in \(model.currency.rawValue) are fine. You can replace them with "
                                + "your statements later.")
            VStack(alignment: .leading, spacing: Metrics.m) {
                groupTitle("What you have today")
                OnboardingNumberRow("Cash and savings", value: $model.answers.cash, unit: symbol)
                OnboardingNumberRow("Investments", value: $model.answers.investments, unit: symbol)
                OnboardingNumberRow("Pension you can't access yet", value: $model.answers.pension, unit: symbol)
                if (model.answers.pension ?? 0) > 0 {
                    Stepper("Available from age \(pensionAge.wrappedValue)", value: pensionAge, in: 50...75)
                        .font(.subheadline)
                }
                OnboardingNumberRow("Your home's value", value: $model.answers.home, unit: symbol,
                                    prompt: "Optional")
                if (model.answers.home ?? 0) > 0 || (model.answers.mortgage ?? 0) > 0 {
                    OnboardingNumberRow("Mortgage still owed", value: $model.answers.mortgage, unit: symbol,
                                        prompt: "Optional")
                }
            }
            .onboardingCard()
            VStack(alignment: .leading, spacing: Metrics.m) {
                groupTitle("Each month, after tax")
                Toggle("I've already stopped working", isOn: $model.hasStoppedWorking)
                if !model.hasStoppedWorking {
                    OnboardingNumberRow("Take-home pay", value: $model.answers.payPerMonth, unit: symbol)
                }
                OnboardingNumberRow("Spending", value: $model.answers.spendingPerMonth, unit: symbol)
                if model.answers.hasNegativeAmount {
                    PlanIssueLine(message: "Amounts can't be negative.", isError: true)
                } else if model.hasStoppedWorking {
                    Text("What you live on now, paid from your savings and pensions. Your answer is whether it lasts.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let line = OnboardingText.savingLine(model.answers, currency: model.currency,
                                                                locale: locale) {
                    AmountSentenceText(line)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("If you're not sure what you spend, enter your pay minus what you save.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            .onboardingCard()
        }
    }

    private var pensionAge: Binding<Int> {
        Binding(get: { model.answers.pensionFromAge ?? CountryDefaults.pensionPotAge(for: model.country) },
                set: { model.answers.pensionFromAge = $0 })
    }

    /// The currency's symbol, inside each amount's field: "€".
    private var symbol: String {
        AmountFormat.symbol(for: model.currency, locale: locale)
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.secondaryInk)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Pension and retirement: a state pension (the one input that moves the answer
/// most), when to stop and what you'd spend then (neither once you've
/// stopped working), and the tax on investments, suggested for the
/// country.
struct OnboardingLaterStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Metrics.l) {
            OnboardingTitle("Pension and retirement")
            VStack(alignment: .leading, spacing: Metrics.m) {
                groupTitle(CountryDefaults.statePensionName(for: model.country))
                Stepper("From age \(statePensionAge.wrappedValue)", value: statePensionAge, in: 55...75)
                OnboardingNumberRow("Amount per month", value: $model.answers.statePensionPerMonth, unit: symbol,
                                    prompt: "None")
                Text(OnboardingText.statePensionNote(country: model.country))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onboardingCard()
            if !model.hasStoppedWorking {
                VStack(alignment: .leading, spacing: Metrics.m) {
                    groupTitle("When do you want to retire?")
                    Picker("When", selection: $model.retiresAtChosenAge) {
                        Text("As early as possible").tag(false)
                        Text("At a set age").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if model.retiresAtChosenAge {
                        Stepper("Retire at \(model.chosenAge)", value: $model.chosenAge,
                                in: OnboardingScreen.retirementAges)
                    }
                    OnboardingNumberRow("Spending in retirement", value: $model.answers.retiredSpendingPerMonth,
                                        unit: symbol, prompt: sameSpending)
                    Text("A month, after tax, in today's money. Leave it empty to spend what you spend now.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .onboardingCard()
                .onChange(of: model.retiresAtChosenAge) { _, chosen in
                    if chosen { model.chosenAge = model.suggestedAge }
                }
            }
            VStack(alignment: .leading, spacing: Metrics.m) {
                OnboardingNumberRow("Tax on investment gains", value: taxBinding, kind: .percent, unit: "%",
                                    prompt: "None")
                Text(OnboardingText.taxNote(country: model.country, isDefault: model.taxIsDefault, locale: locale))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onboardingCard()
        }
    }

    private var statePensionAge: Binding<Int> {
        Binding(get: { model.answers.statePensionFromAge ?? CountryDefaults.statePensionAge(for: model.country) },
                set: { model.answers.statePensionFromAge = $0 })
    }

    /// The currency's symbol, inside each amount's field: "€".
    private var symbol: String {
        AmountFormat.symbol(for: model.currency, locale: locale)
    }

    /// Spending in retirement's placeholder: today's spending, which an
    /// empty field keeps.
    private var sameSpending: String {
        guard let spending = model.answers.spendingPerMonth else { return "Same as now" }
        return PlanNumberText.text(spending, kind: .amount, locale: locale)
    }

    private var taxBinding: Binding<Decimal?> {
        Binding(get: { model.answers.investmentTax }, set: { model.setInvestmentTax($0) })
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.secondaryInk)
            .accessibilityAddTraits(.isHeader)
    }
}

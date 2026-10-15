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
            Text("Tell it roughly what you have, earn and spend. In about three minutes you'll have a first answer.")
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Metrics.l) {
                OnboardingRow(title: "An honest answer.", systemImage: AppSymbol.plan,
                              detail: "An age, and how sure, across thousands of possible markets.")
                OnboardingRow(title: "A few minutes a month.", systemImage: AppSymbol.checkIn,
                              detail: "Import your statements, and see how the answer moved.")
                OnboardingRow(title: "Yours alone.", systemImage: "doc.text",
                              detail: "Plain files in your iCloud Drive or on this device. No account, no server.")
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
                            detail: "Your answer is an age, so your birth date is the one thing it can't do without.")
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
                    .disabled(!library.isICloudAvailable)
                Text(library.isICloudAvailable
                     ? "Your iPhone and Mac share it. Turn off to keep it on this device only."
                     : "iCloud Drive is off, so it's kept on this device. You can move it to iCloud Drive later in "
                        + "Settings.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onboardingCard()
        }
    }

    /// The picker, always there: it shows a suggestion, saved once a date
    /// is picked or *Use This Date* is tapped, so none is made up. Without
    /// one the library is still created, and the answer asks for it.
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
                    Text("Not set yet: pick your birth date, or use the one shown.")
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

/// Your money, roughly: what you have today, in four plain buckets that
/// become the starting estimates, and pay and spending a month, with what
/// you save as you type.
struct OnboardingMoneyStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Metrics.l) {
            OnboardingTitle("Your money, roughly",
                            detail: "Round numbers are fine, in \(model.currency.rawValue). Your statements replace "
                                + "them later.")
            VStack(alignment: .leading, spacing: Metrics.m) {
                groupTitle("What you have today")
                PlanNumberRow("Cash and savings", value: $model.answers.cash)
                PlanNumberRow("Investments", value: $model.answers.investments)
                PlanNumberRow("In a pension you can't touch yet", value: $model.answers.pension)
                if (model.answers.pension ?? 0) > 0 {
                    Stepper("You can draw it from \(pensionAge.wrappedValue)", value: pensionAge, in: 50...75)
                        .font(.subheadline)
                }
                PlanNumberRow("Home, minus the mortgage", value: $model.answers.home, prompt: "Optional")
            }
            .onboardingCard()
            VStack(alignment: .leading, spacing: Metrics.m) {
                groupTitle("Each month, after tax")
                PlanNumberRow("Take-home pay", value: $model.answers.payPerMonth)
                PlanNumberRow("Spending", value: $model.answers.spendingPerMonth)
                if model.answers.hasNegativeAmount {
                    PlanIssueLine(message: "Amounts can't be negative.", isError: true)
                } else if let line = OnboardingText.savingLine(model.answers, currency: model.currency,
                                                                locale: locale) {
                    AmountSentenceText(line)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Not sure about spending? Pay minus what you save.")
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

    private func groupTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.secondaryInk)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Later in life: a state pension (the one input that moves the answer
/// most), when to stop, and the tax on investments, suggested for the
/// country.
struct OnboardingLaterStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(\.locale) private var locale

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Metrics.l) {
            OnboardingTitle("Later in life")
            VStack(alignment: .leading, spacing: Metrics.m) {
                groupTitle(CountryDefaults.statePensionName(for: model.country))
                Stepper("From age \(statePensionAge.wrappedValue)", value: statePensionAge, in: 55...75)
                PlanNumberRow("About, a month", value: $model.answers.statePensionPerMonth, prompt: "None")
                Text(OnboardingText.statePensionNote(country: model.country))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onboardingCard()
            VStack(alignment: .leading, spacing: Metrics.m) {
                groupTitle("When would you like to stop?")
                Picker("When", selection: $model.retiresAtChosenAge) {
                    Text("As early as works").tag(false)
                    Text("At an age I choose").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if model.retiresAtChosenAge {
                    Stepper("Retire at \(model.chosenAge)", value: $model.chosenAge,
                            in: OnboardingScreen.retirementAges)
                }
            }
            .onboardingCard()
            .onChange(of: model.retiresAtChosenAge) { _, chosen in
                if chosen { model.chosenAge = model.suggestedAge }
            }
            VStack(alignment: .leading, spacing: Metrics.m) {
                PlanNumberRow("Tax on investment gains", value: taxBinding, kind: .percent, unit: "%",
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

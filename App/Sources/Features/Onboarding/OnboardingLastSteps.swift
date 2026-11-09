import CloudSync
import Glance
import Model
import SwiftUI

/// Keep your answer up to date (UI.md, "Empty states and first launch"):
/// how the rough amounts get replaced, one of three
/// (``OnboardingModel/KeepUp``), each saying what it gives.
///
/// - *Type your balances*: the starting estimates, each in a field to name
///   it, become your accounts whose values you type, with what moved, at
///   each check-in; *Continue* makes them so
///   (`LibraryStore.adoptStartingEstimates(names:)`).
/// - *Import your statements*: which files work, the starter spreadsheet
///   for what has no export, and on the iPhone and iPad that importing is
///   easiest on the Mac; *Import Files…* pushes the import on the tour's
///   stack.
/// - *Decide later*: the estimates stay, and Today's card says how to
///   update them.
struct OnboardingKeepUpStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            OnboardingTitle("Keep your answer up to date",
                            detail: "Your answer uses the rough amounts you entered. Choose how you'd like to "
                                + "update them. You can change this for each account later.")
            option(.type, title: "Type your balances",
                   detail: "At each check-in, type what each account holds. You also type what came in, what you "
                    + "spent and what you added.",
                   gives: "Everything on the previous step: your answer, net worth, milestones, savings rate and "
                    + "what moved your money.")
            if model.keepUp == .type, !library.library.openStartingEstimates.isEmpty {
                OnboardingEstimateNames()
            }
            option(.importFiles, title: "Import your statements",
                   detail: "CSV exports from your bank and broker fill in everything, line by line.",
                   gives: "The same, filled in from your files, plus your holdings, gains and live prices.")
            if model.keepUp == .importFiles {
                OnboardingImportFiles()
            }
            option(.later, title: "Decide later",
                   detail: "Keep your rough amounts for now. Today shows how to update them.", gives: nil)
        }
    }

    private func option(_ choice: OnboardingModel.KeepUp, title: String, detail: String,
                        gives: String?) -> some View {
        let isChosen = model.keepUp == choice
        return Button {
            withAnimation { model.keepUp = choice }
        } label: {
            HStack(alignment: .top, spacing: Metrics.m) {
                Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                    .font(.app(.title3))
                    .foregroundStyle(isChosen ? Palette.accent : Palette.mutedInk)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Metrics.xs) {
                    Text(title)
                        .font(.app(.headline))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(.app(.subheadline))
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if let gives {
                        Text(gives)
                            .font(.app(.footnote))
                            .foregroundStyle(Palette.accentDeep)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onboardingCard()
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(isChosen ? Palette.accent : .clear, lineWidth: 2)
        }
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// *Type your balances*: each starting estimate in a field to name it,
/// with its kind and amount, and what each check-in will ask.
private struct OnboardingEstimateNames: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text("Your accounts")
                .font(.app(.subheadline).weight(.semibold))
                .foregroundStyle(Palette.secondaryInk)
            Text("Your rough amounts become these accounts. Rename them to match yours.")
                .font(.app(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(library.library.openStartingEstimates) { estimate in
                HStack(spacing: Metrics.m) {
                    TextField("Name", text: name(of: estimate))
                        .textFieldStyle(.plain)
                        .typedFieldOutline(isFocused: false)
                        .accessibilityLabel(Text("Name of \(OnboardingKeepUpText.kindName(estimate))"))
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(OnboardingKeepUpText.kindName(estimate))
                            .font(.app(.caption))
                            .foregroundStyle(Palette.secondaryInk)
                        if let balance = library.library.valuations(for: estimate.id).last?.balance {
                            AmountText(abs(balance), currency: estimate.currency)
                                .font(.app(.caption))
                                .foregroundStyle(Palette.secondaryInk)
                        }
                    }
                }
            }
            Divider()
            Text("At each check-in you type each account's balance and what moved: what came in, what went out "
                + "and the interest for your savings, what you added for your investments and pension. Type 0 when "
                + "nothing moved. It takes about a minute a month.")
                .font(.app(.footnote))
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onboardingCard()
    }

    /// The name typed for `estimate`, its own without "(estimate)" until
    /// one is.
    private func name(of estimate: Account) -> Binding<String> {
        Binding(get: { model.estimateNames[estimate.id] ?? OnboardingKeepUpText.suggestedName(estimate) },
                set: { model.estimateNames[estimate.id] = $0 })
    }
}

/// *Import your statements*: which files work and where they come from,
/// the starter spreadsheet for what has no export, and the Mac.
private struct OnboardingImportFiles: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            OnboardingRow(title: "Bank statements", systemImage: "building.columns",
                          detail: "A CSV export from your bank's website, usually found with your account's "
                            + "transactions. You can import several at once.")
            OnboardingRow(title: "Broker exports", systemImage: "chart.line.uptrend.xyaxis",
                          detail: "A CSV export of your transactions from your broker.")
            OnboardingRow(title: "Home, pension, debts", systemImage: "house",
                          detail: "Fill in the starter spreadsheet with one row per date and one column per "
                            + "account, then import it. Or type their balances at each check-in.") {
                StarterSpreadsheetButton()
                    .padding(.top, Metrics.xs)
            }
            #if os(iOS)
            Label(library.location?.kind == .iCloud
                  ? "Importing is easier on a Mac. Open Last Monday there; your library is already in iCloud "
                    + "Drive."
                  : "Importing is easier on a Mac, where your files usually are.",
                  systemImage: "macbook.and.iphone")
                .font(.app(.body))
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            #endif
            if !library.library.openStartingEstimates.isEmpty {
                Text("After each import, you can replace your rough amounts with the accounts it added.")
                    .font(.app(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onboardingCard()
    }
}

/// The words of *Keep your answer up to date*, free of SwiftUI.
enum OnboardingKeepUpText {
    /// What an estimate becomes: "Savings", "Investments", "Pension fund".
    static func kindName(_ estimate: Account) -> String {
        estimate.kind == .other ? "Investments" : estimate.kind.displayName
    }

    /// "Cash and savings" for "Cash and savings (estimate)".
    static func suggestedName(_ estimate: Account) -> String {
        let suffix = " (estimate)"
        return estimate.name.hasSuffix(suffix) ? String(estimate.name.dropLast(suffix.count)) : estimate.name
    }
}

/// Reminders: the monthly note, shown with your own answer before
/// it's turned on, and *Your year*; the widget, suggested once; and the
/// disclaimer in a line, with the whole text a tap away. *Start* turns on
/// the notes ticked and opens Today.
struct OnboardingNotesStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(WidgetStore.self) private var widgets
    @Environment(\.locale) private var locale
    @State private var readsMore = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Metrics.l) {
            OnboardingTitle("Reminders",
                            detail: "The app can send you a short note once a month. Notes never show amounts.")
            if let note = monthlyNote {
                notePreview(note)
            }
            VStack(alignment: .leading, spacing: Metrics.m) {
                Toggle("Monthly note", isOn: $model.monthlyNote)
                Toggle("Your year, in January", isOn: $model.yourYearNote)
            }
            .onboardingCard()
            widgetHint
            HStack(spacing: Metrics.s) {
                Text(AboutText.disclaimer)
                    .font(.app(.footnote))
                    .foregroundStyle(Palette.secondaryInk)
                Button("Read More") { readsMore = true }
                    .font(.app(.footnote))
                    .buttonStyle(.borderless)
                    .popover(isPresented: $readsMore) {
                        ScrollView {
                            Text(AboutText.about)
                                .font(.app(.body))
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(Metrics.l)
                        }
                        .frame(idealWidth: 360, maxWidth: 420, maxHeight: 420)
                        .presentationCompactAdaptation(.sheet)
                    }
            }
        }
    }

    /// This month's note as it would come, with the answer in it.
    private var monthlyNote: EngagementNote? {
        guard let snapshot = widgets.snapshot() else { return nil }
        return NotePlanner.notes(for: snapshot, settings: NoteSettings(monthly: true, yourYear: false),
                                 now: .now(), locale: locale).first
    }

    private func notePreview(_ note: EngagementNote) -> some View {
        HStack(alignment: .top, spacing: Metrics.m) {
            Image(systemName: AppSymbol.today)
                .font(.app(.title3))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(note.title)
                        .font(.app(.subheadline).weight(.semibold))
                    Spacer()
                    Text(AmountFormat.shortDate(note.time.date, locale: locale))
                        .font(.app(.caption))
                        .foregroundStyle(Palette.secondaryInk)
                }
                Text(note.body)
                    .font(.app(.subheadline))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Palette.ink)
            .privacySensitiveInFeedback()
        }
        .padding(Metrics.m)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("A note like this one: \(note.title). \(note.body)"))
    }

    /// The widget, suggested once: where to add it.
    private var widgetHint: some View {
        HStack(alignment: .top, spacing: Metrics.m) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.app(.title2))
                .foregroundStyle(Palette.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(Self.widgetTitle)
                    .font(.app(.headline))
                    .foregroundStyle(Palette.ink)
                Text(Self.widgetHow)
                    .font(.app(.subheadline))
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onboardingCard()
        .accessibilityElement(children: .combine)
    }

    #if os(macOS)
    static let widgetTitle = "On your desktop"
    static let widgetHow = "Control-click the desktop, choose Edit Widgets, then find Last Monday."
    #else
    static let widgetTitle = "On your Lock Screen"
    static let widgetHow = "Touch and hold the Lock Screen, tap Customize, then add Last Monday."
    #endif
}

/// *Start*: turns on the notes ticked (asking to allow notifications), and
/// opens Today.
struct OnboardingStartButton: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(AppPreferences.self) private var preferences
    @Environment(NoteStore.self) private var notes

    var body: some View {
        Button("Start") { start() }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
    }

    private func start() {
        if model.monthlyNote || model.yourYearNote, !preferences.notes.isAnyOn {
            let settings = NoteSettings(monthly: model.monthlyNote, yourYear: model.yourYearNote)
            Task { await notes.apply(settings) }
        }
        navigation.showToday()
        navigation.finishesOnboarding = false
    }
}

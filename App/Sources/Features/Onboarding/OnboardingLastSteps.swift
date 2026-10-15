import CloudSync
import Glance
import Model
import SwiftUI

/// Make it real (UI.md, "Empty states and first launch"): files come after
/// the answer, as the way to sharpen it. Which files work and where they
/// come from, the starter spreadsheet for what has no export, and on the
/// iPhone and iPad that importing is easiest on the Mac. *Import Files…*
/// pushes the import on the tour's stack; *Later* is a real choice.
struct OnboardingFilesStep: View {
    /// Pushes the import.
    let importFiles: () -> Void

    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            OnboardingTitle("Make it real",
                            detail: "Your answer is as good as its numbers. Swap the round ones for your statements, "
                                + "now or at your first check-in.")
            VStack(alignment: .leading, spacing: Metrics.l) {
                OnboardingRow(title: "Bank statements", systemImage: "building.columns",
                              detail: "A CSV export from your bank's website, usually under your account's "
                                + "transactions. Several at once is fine.")
                OnboardingRow(title: "Broker exports", systemImage: "chart.line.uptrend.xyaxis",
                              detail: "Your transactions, as CSV.")
                OnboardingRow(title: "Home, pension, debts", systemImage: "house",
                              detail: "Fill in the starter spreadsheet: one row per date, one column per account. "
                                + "Then import it.") {
                    StarterSpreadsheetButton()
                        .padding(.top, Metrics.xs)
                }
            }
            .onboardingCard()
            #if os(iOS)
            Label(library.location?.kind == .iCloud
                  ? "Importing is easiest on a Mac. Open Can I Retire Yet there: your library is already in iCloud "
                    + "Drive."
                  : "Importing is easiest on a Mac, with your files at hand.",
                  systemImage: "macbook.and.iphone")
                .font(.callout)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            #endif
            if !library.library.openStartingEstimates.isEmpty {
                Text("After each import you can replace your round amounts with the accounts it brought in.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Keep it in view: the monthly note, shown with your own answer before
/// it's turned on, and *Your year*; the widget, suggested once; and the
/// disclaimer in a line, with the whole text a tap away. *Start* turns on
/// the notes ticked and opens the Overview.
struct OnboardingNotesStep: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(WidgetStore.self) private var widgets
    @Environment(\.locale) private var locale
    @State private var readsMore = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Metrics.l) {
            OnboardingTitle("Keep it in view", detail: "Once a month, a short note. Never amounts.")
            if let note = monthlyNote {
                notePreview(note)
            }
            VStack(alignment: .leading, spacing: Metrics.m) {
                Toggle("Monthly note", isOn: $model.monthlyNote)
                Toggle("Your year, each January", isOn: $model.yourYearNote)
            }
            .onboardingCard()
            widgetHint
            HStack(spacing: Metrics.s) {
                Text(AboutText.disclaimer)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                Button("Read More") { readsMore = true }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                    .popover(isPresented: $readsMore) {
                        ScrollView {
                            Text(AboutText.about)
                                .font(.callout)
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
                                 now: NoteStore.now(), locale: locale).first
    }

    private func notePreview(_ note: EngagementNote) -> some View {
        HStack(alignment: .top, spacing: Metrics.m) {
            Image(systemName: AppSymbol.overview)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(note.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(AmountFormat.shortDate(note.time.date, locale: locale))
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Text(note.body)
                    .font(.subheadline)
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
                .font(.title2)
                .foregroundStyle(Palette.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(Self.widgetTitle)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(Self.widgetHow)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onboardingCard()
        .accessibilityElement(children: .combine)
    }

    #if os(macOS)
    static let widgetTitle = "On your desktop"
    static let widgetHow = "Control-click the desktop, choose Edit Widgets, then find Can I Retire Yet."
    #else
    static let widgetTitle = "On your Lock Screen"
    static let widgetHow = "Touch and hold the Lock Screen, tap Customize, then add Time to retire."
    #endif
}

/// *Start*: turns on the notes ticked (asking to allow notifications), and
/// opens the Overview.
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
        navigation.showOverview()
        navigation.finishesOnboarding = false
    }
}

import CloudSync
import Glance
import Model
import Planner
import SwiftUI

/// First launch (UI.md, "Empty states and first launch"): a short tour to
/// a first answer from round numbers, then ways to make it real.
///
/// 1. The question the app answers (``OnboardingWelcome``).
/// 2. About you: birth date, country (which sets the currency and names
///    the inflation index), and iCloud Drive (``OnboardingYouStep``).
/// 3. Your money, roughly: what you have today, pay and spending a month
///    (``OnboardingMoneyStep``).
/// 4. Later in life: a state pension, when to stop, the tax on investments
///    (``OnboardingLaterStep``). *See My Answer* creates the library, the
///    starting estimates and the first plan (``OnboardingModel/seeAnswer(library:plans:navigation:preferences:)``).
/// 5. The answer, calculated here (``OnboardingAnswerStep``).
/// 6. Make it real: which files to import, the starter spreadsheet, the
///    Mac (``OnboardingFilesStep``); *Import Files…* pushes the import on
///    the tour's own stack.
/// 7. Keep it in view: the monthly note, the widget and the disclaimer
///    (``OnboardingNotesStep``); *Start* opens the Overview.
///
/// On the Mac and iPad the money and later-in-life steps have a quick
/// estimate beside them (``OnboardingEstimatePanel``). What's typed lives
/// in ``OnboardingModel``, so it survives the opening screen the root view
/// shows while the new library opens. The root view keeps showing the tour
/// after the library is created, while `AppNavigation.finishesOnboarding`
/// is set.
struct OnboardingScreen: View {
    /// What the tour pushes on its own stack.
    private enum Destination: Hashable {
        case importFile
    }

    /// The ages to retire at that can be chosen, as in the plan's editor.
    static let retirementAges = 30...85

    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(AppPreferences.self) private var preferences
    @Environment(OnboardingModel.self) private var model
    @Environment(\.pageLayout) private var layout

    @State private var path: [Destination] = []

    init() {}

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.xl) {
                    stepContent
                    if let error = model.error {
                        StatusBanner(.error, "Couldn't create the library", message: error, personal: .message)
                    }
                }
                .padding(Metrics.xl)
                .frame(maxWidth: showsEstimate ? 900 : 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Palette.page)
            .safeAreaInset(edge: .bottom) { buttons }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .importFile:
                    ImportScreen(close: { path = [] })
                        .navigationBarBackButtonHidden()
                }
            }
        }
        .onAppear {
            if !library.isICloudAvailable { model.keepsInICloud = false }
            if let requested = navigation.requestedOnboardingStep {
                model.step = requested
                navigation.requestedOnboardingStep = nil
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome:
            OnboardingWelcome()
        case .you:
            OnboardingYouStep()
        case .money, .later:
            if showsEstimate {
                HStack(alignment: .top, spacing: Metrics.xl) {
                    questions
                        .frame(maxWidth: 520, alignment: .leading)
                    OnboardingEstimatePanel()
                        .frame(width: 300)
                }
            } else {
                questions
            }
        case .answer:
            OnboardingAnswerStep()
        case .files:
            OnboardingFilesStep { path.append(.importFile) }
        case .notes:
            OnboardingNotesStep()
        }
    }

    @ViewBuilder
    private var questions: some View {
        if model.step == .money {
            OnboardingMoneyStep()
        } else {
            OnboardingLaterStep()
        }
    }

    /// The quick estimate shows beside the money and later-in-life steps
    /// on the Mac and iPad, where there's room for it.
    private var showsEstimate: Bool {
        layout.isWide && (model.step == .money || model.step == .later)
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: Metrics.m) {
            if let previous = model.step.previous {
                Button("Back") {
                    withAnimation { model.step = previous }
                }
                .disabled(model.isCreating)
            }
            Spacer()
            if let number = model.step.questionNumber {
                Text("Step \(number) of \(OnboardingStep.questionCount)")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .monospacedDigit()
            }
            Spacer()
            primaryButton
        }
        .padding(Metrics.l)
        .background(.bar)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch model.step {
        case .welcome:
            Button("Get Started") { advance() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .you, .money:
            Button("Continue") { advance() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.answers.hasNegativeAmount)
        case .later:
            Button {
                Task { await model.seeAnswer(library: library, plans: plans, navigation: navigation,
                                             preferences: preferences) }
            } label: {
                if model.isCreating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("See My Answer")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(model.isCreating || model.answers.hasNegativeAmount)
        case .answer:
            Button("Make It Real") { advance() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .files:
            HStack(spacing: Metrics.m) {
                Button(hasImported ? "Continue" : "Later") { advance() }
                    .buttonStyle(.bordered)
                Button("Import Files…") { path.append(.importFile) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!library.canEdit)
            }
        case .notes:
            OnboardingStartButton()
        }
    }

    /// Whether files were imported in the tour: an account that isn't an
    /// estimate has values.
    private var hasImported: Bool {
        library.library.accounts.values.contains { account in
            !account.isStartingEstimate && !library.library.valuations(for: account.id).isEmpty
        }
    }

    private func advance() {
        withAnimation { model.step = model.step.next ?? model.step }
    }
}

extension View {
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

/// A title over a line: each step's top.
struct OnboardingTitle: View {
    let title: String
    let detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// An icon, a title and a line: the welcome's promises and the files to
/// import.
struct OnboardingRow<Accessory: View>: View {
    let title: String
    let systemImage: String
    let detail: String
    private let accessory: Accessory

    init(title: String, systemImage: String, detail: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.accessory = accessory()
    }

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
                accessory
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension OnboardingRow where Accessory == EmptyView {
    init(title: String, systemImage: String, detail: String) {
        self.init(title: title, systemImage: systemImage, detail: detail) { EmptyView() }
    }
}

#Preview("Onboarding") {
    OnboardingScreen()
        .previewEnvironment(PreviewLibrary.empty)
}

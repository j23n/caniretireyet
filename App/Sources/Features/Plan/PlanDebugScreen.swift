import Model
import Planner
import SwiftUI

/// *Show Calculations…* (UI.md, "Calculations (plan debugger)"): every
/// calculation behind the plan's answer, from `Planner.debugReport`, to
/// check it or give it to someone else.
///
/// The controls choose the retirement age the details are for, what the
/// runs start from and how many runs to trace; *Calculate* runs the plan
/// on screen (with its what-if, unless turned off), off the main actor,
/// with *Cancel*. It never runs on its own. Then the diagnosis, and the
/// report's sections as disclosure groups, each with its line on how to
/// read it. *Export…* writes the report as Markdown or JSON, anonymized by
/// default, to share or save; *Copy as Markdown* copies it.
///
/// A sheet everywhere (large on iPad and the Mac), presented with
/// `.planDebugSheet(isPresented:session:library:isWide:)`. The logic is in
/// `PlanDebugModel` and `PlanDebugContent`.
struct PlanDebugScreen: View {
    /// Mac and iPad: tables as `PageTable`s, a row's detail below its table.
    var isWide: Bool

    @State private var model: PlanDebugModel
    @State private var isExporting = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.baseCurrency) private var baseCurrency

    init(model: PlanDebugModel, isWide: Bool) {
        _model = State(initialValue: model)
        self.isWide = isWide
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.l) {
                PlanDebugControlsCard(model: model, isWide: isWide)
                if let error = model.error {
                    StatusBanner(.error, "The plan couldn't be calculated", message: error)
                }
                if let content = model.content {
                    PlanDebugReportView(model: model, content: content, isWide: isWide)
                        .opacity(model.isRunning ? 0.4 : 1)
                        .animation(.default, value: model.isRunning)
                }
            }
            .padding(Metrics.l)
            .frame(maxWidth: isWide ? 1_200 : Metrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        // The report's amounts are in its currency.
        .environment(\.baseCurrency, model.content?.currency ?? baseCurrency)
        .navigationTitle("Calculations")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isExporting = true
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                .help("Share or save these calculations, anonymized if you like")
                .disabled(model.report == nil)
            }
        }
        .sheet(isPresented: $isExporting) {
            NavigationStack {
                PlanDebugExportSheet(model: model)
            }
            .environment(\.baseCurrency, model.content?.currency ?? baseCurrency)
            #if os(macOS)
            .frame(minWidth: 420, idealWidth: 480, minHeight: 440, idealHeight: 520)
            #else
            .presentationDetents([.medium, .large])
            #endif
        }
        .onDisappear { model.cancel() }
    }
}

extension View {
    /// Presents the plan debugger for the plan `session` shows: a sheet,
    /// large on iPad and the Mac.
    func planDebugSheet(isPresented: Binding<Bool>, session: PlanSession, library: LibraryStore, isWide: Bool)
        -> some View {
        sheet(isPresented: isPresented) {
            NavigationStack {
                PlanDebugScreen(model: PlanDebugModel { PlanDebugSource.current(session: session, library: library) },
                                isWide: isWide)
            }
            #if os(macOS)
            .frame(minWidth: 720, idealWidth: 1_040, minHeight: 540, idealHeight: 760)
            #else
            .presentationSizing(.page)
            #endif
        }
    }
}

// MARK: - Controls

/// The options and *Calculate* (or the run's progress with *Cancel*).
struct PlanDebugControlsCard: View {
    @Bindable var model: PlanDebugModel
    var isWide: Bool

    var body: some View {
        Card {
            if model.report == nil, !model.isRunning {
                Text(PlanDebugText.introduction)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isWide {
                HStack(alignment: .top, spacing: Metrics.xl) {
                    ageControl
                    startControl
                    pathsControl
                }
            } else {
                VStack(alignment: .leading, spacing: Metrics.l) {
                    ageControl
                    startControl
                    pathsControl
                }
            }
            if model.hasWhatIf {
                Toggle("Include the what-if", isOn: $model.choices.includesWhatIf)
                    .font(.subheadline)
                Text(model.choices.includesWhatIf
                    ? "Runs the plan with the what-if's changes, which aren't saved in it."
                    : "Runs the plan as it is, without the what-if.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            runRow
        } header: {
            SectionHeader("What to calculate", systemImage: "function")
        }
    }

    private var ageControl: some View {
        PlanDebugControl(title: "Details for retiring", explanation: model.choices.age.explanation) {
            Picker("Details for retiring", selection: $model.choices.age) {
                ForEach(PlanDebugAgeChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if model.choices.age == .age {
                Stepper(value: $model.choices.customAge, in: model.ages) {
                    Text("At \(model.choices.customAge)")
                        .monospacedDigit()
                }
            }
        }
    }

    private var startControl: some View {
        PlanDebugControl(title: "Runs start from", explanation: model.choices.start.explanation) {
            Picker("Runs start from", selection: $model.choices.start) {
                ForEach(PlanDebugStartChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            if model.choices.start == .factor {
                Stepper(value: $model.choices.factor, in: PlanDebugChoices.factors, step: 0.5) {
                    Text(verbatim: PlanDebugText.times(model.choices.factor) + " today's")
                        .monospacedDigit()
                }
            }
        }
    }

    private var pathsControl: some View {
        PlanDebugControl(title: "Traced runs",
                         explanation: "Chosen by outcome: the median, a 10th-percentile run, the first that fails, "
                             + "then the 25th, 75th and 90th percentiles. The run with the expected return every "
                             + "year comes on top.") {
            Stepper(value: $model.choices.pathCount, in: PlanDebugChoices.pathCounts) {
                Text(verbatim: model.choices.pathCount == 1 ? "1 run" : "\(model.choices.pathCount) runs")
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var runRow: some View {
        if model.isRunning {
            HStack(alignment: .center, spacing: Metrics.m) {
                ProgressView()
                    .controlSize(.small)
                Text(PlanDebugText.calculating)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Metrics.s)
                Button("Cancel") { model.cancel() }
                    .buttonStyle(.bordered)
            }
            .accessibilityElement(children: .contain)
        } else {
            HStack(spacing: Metrics.m) {
                Button {
                    model.calculate()
                } label: {
                    Label(model.report == nil ? "Calculate" : "Calculate Again", systemImage: "function")
                }
                .buttonStyle(.borderedProminent)
                if let reason = model.staleReason {
                    Label(reason, systemImage: "clock.arrow.circlepath")
                        .font(.footnote)
                        .foregroundStyle(Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// One control with its title above and a line on what it does below.
struct PlanDebugControl<Content: View>: View {
    let title: String
    let explanation: String
    private let content: Content

    init(title: String, explanation: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.explanation = explanation
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            content
            Text(explanation)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 360, alignment: .leading)
    }
}

// MARK: - The report

/// The report: what was run in brief, the diagnosis, then each section.
struct PlanDebugReportView: View {
    let model: PlanDebugModel
    let content: PlanDebugContent
    var isWide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            PlanDebugSummary(content: content)
            Card {
                Text(PlanDebugText.diagnosisNote)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                PlanDebugSentences(sentences: content.diagnosis)
            } header: {
                SectionHeader("Diagnosis", systemImage: "stethoscope")
            }
            ForEach(content.sections) { section in
                PlanDebugSectionCard(model: model, content: content, section: section, isWide: isWide)
            }
        }
    }
}

/// "Retiring at 38 (today's age) · 2.000 runs · 4 Oct 2026", what the
/// runs start from when it's a multiple of today's plan assets, and the
/// what-if.
struct PlanDebugSummary: View {
    let content: PlanDebugContent

    @Environment(\.locale) private var locale
    @Environment(\.hidesAmounts) private var hidesAmounts

    var body: some View {
        let header = content.report.header
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(verbatim: [
                PlanDebugText.retiring(header),
                PlanDebugValue.count(header.runs).text(currency: content.currency, locale: locale)
                    + (header.fast ? " runs (quick)" : " runs"),
                "calculated " + AmountFormat.mediumDate(header.runDate, locale: locale),
            ].joined(separator: " · "))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.ink)
            if let scale = PlanDebugText.scale(content.report) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Metrics.xs) {
                            Text("The percentiles, failures and traced runs start from")
                            AmountText(PlanDebugValue.whole(header.startAssets))
                        }
                        let sentence = scale.prefix(1).uppercased() + scale.dropFirst() + ". The rest is about "
                            + "today's plan assets."
                        Text(verbatim: hidesAmounts ? PlanDebugText.masked(sentence, currency: content.currency.rawValue)
                            : sentence)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityElement(children: .combine)
            }
            ForEach(content.notes, id: \.self) { note in
                Label(note, systemImage: "slider.horizontal.3")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A section as a disclosure group: its title and line on how to read it,
/// opening to its blocks, charts and tables.
struct PlanDebugSectionCard: View {
    let model: PlanDebugModel
    let content: PlanDebugContent
    let section: PlanDebugSection
    var isWide: Bool

    private var isExpanded: Binding<Bool> {
        Binding(get: { model.isExpanded(section) }, set: { model.setExpanded(section, $0) })
    }

    var body: some View {
        Card {
            DisclosureGroup(isExpanded: isExpanded) {
                VStack(alignment: .leading, spacing: Metrics.l) {
                    PlanDebugSectionBody(model: model, content: content, section: section, isWide: isWide)
                }
                .padding(.top, Metrics.m)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label(section.title, systemImage: section.systemImage)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(section.howToRead(content.report))
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                #if os(macOS)
                // On the Mac, clicking the title opens it too, like its triangle.
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation { model.setExpanded(section, !model.isExpanded(section)) }
                }
                #endif
            }
        }
    }
}

/// What a section shows once opened.
struct PlanDebugSectionBody: View {
    @Bindable var model: PlanDebugModel
    let content: PlanDebugContent
    let section: PlanDebugSection
    var isWide: Bool

    var body: some View {
        switch section {
        case .simulation:
            SuccessCurveChart(points: content.successPoints, threshold: content.report.header.confidence,
                              highlightedAge: content.report.simulation.earliestAge)
            PlanDebugBlocksView(blocks: content.blocks(section), isWide: isWide)
        case .percentiles:
            FanChart(fan: content.fan, markers: content.fanMarkers, showsLegend: true)
            PlanDebugBlocksView(blocks: content.blocks(section), isWide: isWide)
        case .schedule:
            schedule
        case .paths:
            PlanDebugPathsView(model: model, content: content, isWide: isWide)
        case .issues:
            issues
        default:
            PlanDebugBlocksView(blocks: content.blocks(section), isWide: isWide)
        }
    }

    /// The schedule, a year chosen shown line by line.
    @ViewBuilder
    private var schedule: some View {
        Text(isWide ? "Choose a year to see it line by line." : "Open a year to see it line by line.")
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
        ForEach(content.blocks(.schedule)) { block in
            PlanDebugBlockView(block: block, isWide: isWide, selection: $model.selectedScheduleYear,
                               detail: { content.scheduleDetail($0) })
        }
        if isWide, let year = model.selectedScheduleYear {
            Divider()
            PlanDebugBlocksView(blocks: content.scheduleDetail(year), isWide: isWide)
        }
    }

    @ViewBuilder
    private var issues: some View {
        if content.issues.isEmpty {
            Text("None.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
        } else {
            ForEach(content.issues) { issue in
                PlanDebugIssueRow(issue: issue)
            }
        }
    }
}

/// A warning or an error, with its icon and code.
struct PlanDebugIssueRow: View {
    let issue: PlanDebugIssue

    @Environment(\.baseCurrency) private var currency
    @Environment(\.hidesAmounts) private var hidesAmounts

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Image(systemName: issue.isError ? "xmark.octagon" : "exclamationmark.triangle")
                .foregroundStyle(issue.isError ? Palette.critical : Palette.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: issue.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.secondaryInk)
                Text(verbatim: hidesAmounts ? PlanDebugText.masked(issue.message, currency: currency.rawValue)
                    : issue.message)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The traced runs: a picker of runs, what the run is and how it ends, its
/// years (returns and balances, or money in and out), and a year in detail.
struct PlanDebugPathsView: View {
    @Bindable var model: PlanDebugModel
    let content: PlanDebugContent
    var isWide: Bool

    var body: some View {
        if content.paths.isEmpty {
            Text("No runs were traced: choose at least one traced run above, then calculate again.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
        } else {
            Picker("Run", selection: $model.selectedPath) {
                ForEach(content.paths) { path in
                    Text(path.label).tag(path.id)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            if let path = model.path {
                PlanDebugLinesView(lines: path.summary)
                if let reason = path.failureReason {
                    PlanDebugSentences(sentences: [reason])
                }
                Picker("Show", selection: $model.pathTable) {
                    ForEach(PlanDebugPathTable.allCases) { table in
                        Text(table.title).tag(table)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Text(isWide ? "Choose a year to see every step of it below." : "Open a year to see every step of it.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                let table = model.pathTable == .balances ? path.balances : path.flows
                if isWide {
                    PlanDebugTableView(table: table, isWide: true, selection: $model.selectedPathYear)
                    if let year = model.selectedPathYear {
                        Divider()
                        PlanDebugBlocksView(blocks: content.pathDetail(path.id, year: year), isWide: true)
                    }
                } else {
                    PlanDebugTableView(table: table, isWide: false, detail: { content.pathDetail(path.id, year: $0) })
                        .id(table.id)
                }
            }
        }
    }
}

/// The preview library's base plan, for previews: *Calculate* runs the
/// real Planner on it.
@MainActor
private func previewDebugModel() -> PlanDebugModel {
    let library = PreviewLibrary.library
    return PlanDebugModel {
        library.plans["base"].map { PlanDebugSource(plan: $0, library: library, asOf: .today(), revision: 0) }
    }
}

#Preview("Calculations · iPhone") {
    NavigationStack {
        PlanDebugScreen(model: previewDebugModel(), isWide: false)
    }
    .previewEnvironment()
}

#Preview("Calculations · Mac") {
    NavigationStack {
        PlanDebugScreen(model: previewDebugModel(), isWide: true)
    }
    .previewEnvironment()
    .frame(width: 1_040, height: 760)
}

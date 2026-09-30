import Model
import Planner
import SwiftUI
import TaxKit

// The list sections of Inputs (work phases, pensions, events, taxes) and
// the sheets that edit one item. Regime pickers offer only what fits, and
// regime, scheme and system options are forms generated from their
// `OptionField`s (TAXES.md, "Choosing them in a plan").

// MARK: - Lists

/// Work phases as rows ("Employee · 2026–28"); a row opens its editor.
struct PlanWorkList: View {
    let plan: PlanDocument
    let summaries: PlanInputSummaries
    let issues: PlanInputIssues
    @Binding var editing: PlanEditTarget?
    @Environment(LibraryStore.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            ForEach(plan.work.indices, id: \.self) { index in
                let phase = plan.work[index]
                PlanListRow(title: "\(PlanWorkText.kindName(phase.kind)) · \(PlanWorkText.years(of: phase))",
                            detail: summaries.detail(of: phase),
                            issues: issues.issues(for: .work, index: index, regime: phase.regime?.rawValue)) {
                    editing = .work(index: index, phase: phase)
                }
                Divider()
            }
            Button {
                editing = .work(index: plan.work.count,
                                phase: PlanEditing.newWorkPhase(in: plan, asOf: library.asOfDate))
            } label: {
                Label("Add a work phase", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Pensions as rows; adding one asks which scheme.
struct PlanPensionList: View {
    let plan: PlanDocument
    let summaries: PlanInputSummaries
    let issues: PlanInputIssues
    @Binding var editing: PlanEditTarget?
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let schemes = PlanTaxChoices.schemeChoices(for: plan, settings: library.settings,
                                                   registry: AppTaxRegistry.standard)
        VStack(alignment: .leading, spacing: Metrics.xs) {
            ForEach(plan.pensions.indices, id: \.self) { index in
                let pension = plan.pensions[index]
                PlanListRow(title: PlanResultsMapping.pensionName(pension, registry: AppTaxRegistry.standard),
                            detail: summaries.detail(of: pension),
                            issues: issues.issues(for: .pensions, index: index)) {
                    editing = .pension(index: index, pension: pension)
                }
                Divider()
            }
            Menu {
                ForEach(schemes) { scheme in
                    Button(scheme.name) {
                        editing = .pension(index: plan.pensions.count, pension: PlanEditing.newPension(scheme: scheme.id))
                    }
                }
            } label: {
                Label("Add a pension", systemImage: "plus")
            }
            .fixedSize()
        }
    }
}

/// One-off events as rows ("Inheritance · at 62").
struct PlanEventList: View {
    let plan: PlanDocument
    let summaries: PlanInputSummaries
    let issues: PlanInputIssues
    @Binding var editing: PlanEditTarget?
    @Environment(LibraryStore.self) private var library

    private func when(_ event: PlanEvent) -> String {
        switch event.timing {
        case .age(let age): "at \(age)"
        case .year(let year): "in \(String(year))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            ForEach(plan.events.indices, id: \.self) { index in
                let event = plan.events[index]
                PlanListRow(title: "\(event.name) · \(when(event))", detail: summaries.detail(of: event),
                            issues: issues.issues(for: .events, index: index)) {
                    editing = .event(index: index, event: event)
                }
                Divider()
            }
            Button {
                editing = .event(index: plan.events.count, event: PlanEditing.newEvent(asOf: library.asOfDate))
            } label: {
                Label("Add an event", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Taxes: the residence timeline and the special regimes (overlays) with
/// their years as bars, then each as a row; threshold indexing; overrides.
struct PlanTaxesEditor: View {
    @Binding var plan: PlanDocument
    let summaries: PlanInputSummaries
    let issues: PlanInputIssues
    @Binding var editing: PlanEditTarget?
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let registry = AppTaxRegistry.standard
        let overlays = PlanTaxChoices.overlays(for: plan, settings: library.settings, registry: registry)
        VStack(alignment: .leading, spacing: Metrics.s) {
            PlanTaxTimeline(plan: plan, first: library.asOfDate.year, last: lastYear)
            Text("Where you live")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            if plan.tax.residence.isEmpty {
                Text("Not set: \(PlanTaxChoices.defaultSystem(for: library.settings, registry: registry)?.name ?? "no system") applies.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
            ForEach(plan.tax.residence.indices, id: \.self) { index in
                let entry = plan.tax.residence[index]
                PlanListRow(title: summaries.title(of: entry), detail: optionsSummary(entry),
                            issues: issues.residenceIssues(index: index)) {
                    editing = .residence(index: index, residence: entry)
                }
            }
            Button {
                editing = .residence(index: plan.tax.residence.count,
                                     residence: PlanEditing.newResidence(in: plan, asOf: library.asOfDate))
            } label: {
                Label(addResidenceTitle, systemImage: "plus")
            }
            .buttonStyle(.borderless)

            Divider()
            Text("Special regimes")
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            ForEach(plan.tax.overlays.indices, id: \.self) { index in
                let overlay = plan.tax.overlays[index]
                PlanListRow(title: registry.regime(overlay.regime.rawValue)?.regime.name ?? overlay.regime.rawValue,
                            detail: overlayYears(overlay),
                            issues: issues.overlayIssues(regime: overlay.regime.rawValue)) {
                    editing = .overlay(index: index, overlay: overlay)
                }
            }
            if let first = overlays.first {
                Button {
                    editing = .overlay(index: plan.tax.overlays.count, overlay: PlanOverlay(regime: RegimeID(first.id)))
                } label: {
                    Label("Add a special regime", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            Divider()
            Toggle("Raise tax thresholds with inflation", isOn: $plan.tax.planIndexThresholds)
            if !plan.tax.overrides.isEmpty {
                Text("Law changes for this plan: \(plan.tax.overrides.keys.sorted().joined(separator: ", ")). "
                    + "Edit them in the plan file.")
                    .font(.caption)
                    .foregroundStyle(Palette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.subheadline)
    }

    private var addResidenceTitle: String {
        plan.tax.residence.isEmpty ? "Set where you live" : "Add a move"
    }

    /// The last year the plan funds.
    private var lastYear: Int {
        let birth = library.settings.person?.birthDate?.year ?? (library.asOfDate.year - 40)
        return max(library.asOfDate.year + 1, birth + plan.effectiveEndAge)
    }

    /// "Addizionale regionale 1,73% · Addizionale comunale 0,8%".
    private func optionsSummary(_ entry: PlanResidence) -> String {
        let fields = PlanTaxChoices.systemFields(entry.system, registry: AppTaxRegistry.standard)
        return fields.compactMap { field -> String? in
            guard let value = entry.options[field.key] else { return nil }
            let text = PlanOptionForm.text(for: value, kind: field.kind)
            return field.kind == .percent ? "\(field.label) \(text)%" : "\(field.label) \(text)"
        }.joined(separator: " · ")
    }

    private func overlayYears(_ overlay: PlanOverlay) -> String {
        guard let years = PlanTaxChoices.overlayYears(overlay, plan: plan, registry: AppTaxRegistry.standard) else {
            return ""
        }
        return years.end.map { PlanInputSummaries.years(from: years.start, until: $0) } ?? "From \(String(years.start))"
    }
}

/// The residence periods and overlays as bars across the plan's years.
struct PlanTaxTimeline: View {
    let plan: PlanDocument
    let first: Int
    let last: Int
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let residence = PlanTaxChoices.residenceSegments(for: plan, first: first, last: last,
                                                         settings: library.settings, registry: AppTaxRegistry.standard)
        let overlays = PlanTaxChoices.overlaySegments(for: plan, registry: AppTaxRegistry.standard)
        VStack(alignment: .leading, spacing: Metrics.xs) {
            bars(residence, height: 22, overlay: false)
            if !overlays.isEmpty {
                bars(overlays, height: 12, overlay: true)
            }
            HStack {
                Text(String(first))
                Spacer()
                Text(String(last))
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(Palette.mutedInk)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.spoken(residence + overlays)))
    }

    /// "Italy 2026 to 2047, Generic (flat rates) 2048 to 2083".
    private static func spoken(_ segments: [PlanTimelineSegment]) -> String {
        var parts: [String] = []
        for segment in segments {
            let end = segment.isOpenEnded ? "on" : "to " + String(segment.end)
            parts.append(segment.name + " " + String(segment.start) + " " + end)
        }
        return parts.joined(separator: ", ")
    }

    private func bars(_ segments: [PlanTimelineSegment], height: CGFloat, overlay: Bool) -> some View {
        GeometryReader { geometry in
            let span = CGFloat(max(1, last - first + 1))
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                ForEach(segments) { segment in
                    let position = segments.firstIndex(of: segment) ?? 0
                    let start = CGFloat(max(first, segment.start) - first) / span
                    let length = CGFloat(min(last, segment.end) - max(first, segment.start) + 1) / span
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(overlay ? Palette.accent.opacity(segment.isOpenEnded ? 0.35 : 0.6)
                            : Palette.color(for: .series(position % 8)).opacity(0.25))
                        .frame(width: max(4, width * length), height: height)
                        .overlay(alignment: .leading) {
                            if !overlay {
                                Text(segment.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .foregroundStyle(Palette.ink)
                                    .padding(.leading, 4)
                            }
                        }
                        .offset(x: width * start)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Sheets

/// The sheet editing one list item.
struct PlanItemSheet: View {
    let session: PlanSession
    let target: PlanEditTarget
    let issues: PlanInputIssues

    private var plan: PlanDocument { session.editablePlan }

    /// A delete action for an item that exists (not a new one).
    private func deletion(_ exists: Bool, _ action: @escaping () -> Void) -> (() -> Void)? {
        exists ? action : nil
    }

    var body: some View {
        switch target {
        case .work(let index, let phase):
            PlanItemEditor(index < plan.work.count ? "Work phase" : "New work phase", item: phase, onSave: { edited in
                session.edit { $0.work = PlanEditing.replacing(at: index, with: edited, in: $0.work) }
            }, onDelete: deletion(index < plan.work.count) {
                session.edit { $0.work = PlanEditing.removing(at: index, from: $0.work) }
            }) { binding in
                PlanWorkPhaseForm(phase: binding, plan: plan,
                                  issues: issues.issues(for: .work, index: index, regime: phase.regime?.rawValue))
            }
        case .pension(let index, let pension):
            PlanItemEditor(index < plan.pensions.count ? "Pension" : "New pension", item: pension, onSave: { edited in
                session.edit { $0.pensions = PlanEditing.replacing(at: index, with: edited, in: $0.pensions) }
            }, onDelete: deletion(index < plan.pensions.count) {
                session.edit { $0.pensions = PlanEditing.removing(at: index, from: $0.pensions) }
            }) { binding in
                PlanPensionForm(pension: binding, plan: plan, issues: issues.issues(for: .pensions, index: index))
            }
        case .event(let index, let event):
            PlanItemEditor(index < plan.events.count ? "Event" : "New event", item: event, onSave: { edited in
                session.edit { $0.events = PlanEditing.replacing(at: index, with: edited, in: $0.events) }
            }, onDelete: deletion(index < plan.events.count) {
                session.edit { $0.events = PlanEditing.removing(at: index, from: $0.events) }
            }) { binding in
                PlanEventForm(event: binding, issues: issues.issues(for: .events, index: index))
            }
        case .residence(let index, let residence):
            PlanItemEditor("Tax residence", item: residence, onSave: { edited in
                session.edit {
                    $0.tax.residence = PlanEditing.replacing(at: index, with: edited, in: $0.tax.residence)
                        .sorted { $0.from < $1.from }
                }
            }, onDelete: deletion(index < plan.tax.residence.count) {
                session.edit { $0.tax.residence = PlanEditing.removing(at: index, from: $0.tax.residence) }
            }) { binding in
                PlanResidenceForm(residence: binding, issues: issues.residenceIssues(index: index))
            }
        case .overlay(let index, let overlay):
            PlanItemEditor("Special regime", item: overlay, onSave: { edited in
                session.edit { $0.tax.overlays = PlanEditing.replacing(at: index, with: edited, in: $0.tax.overlays) }
            }, onDelete: deletion(index < plan.tax.overlays.count) {
                session.edit { $0.tax.overlays = PlanEditing.removing(at: index, from: $0.tax.overlays) }
            }) { binding in
                PlanOverlayForm(overlay: binding, plan: plan, issues: issues.overlayIssues(regime: overlay.regime.rawValue))
            }
        }
    }
}

/// A list of issues as a form section.
struct PlanIssuesSection: View {
    let issues: [PlanIssue]

    var body: some View {
        if !issues.isEmpty {
            Section {
                ForEach(issues, id: \.self) { issue in
                    PlanIssueLine(issue)
                }
            }
        }
    }
}

// MARK: - Forms

/// A work phase: kind, dates and amounts, the regime (only those that fit
/// the kind of work in these years) and the regime's own options.
struct PlanWorkPhaseForm: View {
    @Binding var phase: WorkPhase
    let plan: PlanDocument
    let issues: [PlanIssue]
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let registry = AppTaxRegistry.standard
        let regimes = PlanTaxChoices.regimes(for: phase, in: plan, settings: library.settings, registry: registry)
        let defaultName = PlanTaxChoices.defaultRegimeName(for: phase, in: plan, settings: library.settings,
                                                           registry: registry)
        let regimeID = PlanTaxChoices.effectiveRegimeID(for: phase, in: plan, settings: library.settings,
                                                        registry: registry)
        let fields = PlanTaxChoices.regimeFields(regimeID, registry: registry)
        let summary = regimeID.flatMap { registry.regime($0)?.regime.summary }
        let defaultLabel: String = defaultName.map { "Default: \($0)" } ?? "Default"
        Section("Work") {
            Picker("Kind", selection: $phase.planKind) {
                ForEach(WorkKind.knownValues, id: \.self) { kind in
                    Text(PlanWorkText.kindName(kind)).tag(kind)
                }
            }
            DatePicker("From", selection: $phase.from.planDate, displayedComponents: .date)
            Toggle("Until retirement", isOn: $phase.planUntilRetirement)
            if !phase.planUntilRetirement {
                DatePicker("Until", selection: $phase.planUntilDate.planDate, displayedComponents: .date)
            }
        }
        Section {
            if phase.kind == .employee {
                PlanNumberRow("Gross salary", value: $phase.grossSalary, unit: "/yr")
            } else if phase.kind == .selfEmployed {
                PlanNumberRow("Revenue", value: $phase.revenue, unit: "/yr")
                PlanNumberRow("Costs", value: $phase.costs, unit: "/yr", prompt: "0")
            } else if phase.kind == .net {
                PlanNumberRow("Net income", value: $phase.netIncome, unit: "/yr")
            }
            PlanNumberRow("Real growth", value: $phase.realGrowth, kind: .percent, unit: "%/yr", prompt: "0")
        } header: {
            Text("Amounts")
        } footer: {
            Text("In today's euros. Growth is above inflation.")
        }
        Section {
            Picker("Regime", selection: $phase.planRegime) {
                Text(defaultLabel).tag("")
                ForEach(regimes, id: \.id) { regime in
                    Text(regime.name).tag(regime.id)
                }
            }
            if let summary {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PlanOptionsForm(fields: fields, options: $phase.options)
        } header: {
            Text("Taxes")
        } footer: {
            Text("Only the regimes that fit this kind of work, in these years, where you live then.")
        }
        PlanIssuesSection(issues: issues)
    }
}

/// A pension: its scheme, name, when to claim (or a fixed amount and age),
/// who taxes it, and the scheme's own options.
struct PlanPensionForm: View {
    @Binding var pension: PlanPension
    let plan: PlanDocument
    let issues: [PlanIssue]
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        let registry = AppTaxRegistry.standard
        let schemes = PlanTaxChoices.schemeChoices(for: plan, settings: library.settings, registry: registry)
        let fields = PlanTaxChoices.pensionOptionFields(scheme: pension.scheme.rawValue, registry: registry)
        Section("Pension") {
            Picker("Scheme", selection: $pension.planScheme) {
                ForEach(schemes) { scheme in
                    Text(scheme.name).tag(scheme.id)
                }
                if !schemes.contains(where: { $0.id == pension.scheme.rawValue }) {
                    Text(pension.scheme.rawValue).tag(pension.scheme.rawValue)
                }
            }
            TextField("Name", text: $pension.planName,
                      prompt: Text(PlanResultsMapping.pensionName(PlanPension(scheme: pension.scheme), registry: registry)))
        }
        if pension.scheme == .fixed {
            Section("From your statement") {
                Stepper("Paid from \(pension.planFromAge)", value: $pension.planFromAge, in: 40...90)
                PlanNumberRow("Gross per year", value: $pension.perYear, unit: "/yr")
            }
        } else {
            Section("When to claim") {
                Toggle("As early as possible", isOn: $pension.planClaimsEarliest)
                if !pension.planClaimsEarliest {
                    Stepper("At \(pension.planClaimAge)", value: $pension.planClaimAge, in: 50...80)
                }
            }
        }
        Section {
            Picker("Taxed by", selection: $pension.planTaxedIn) {
                Text("Where you live").tag(TaxedIn.residence)
                Text("The paying country").tag(TaxedIn.source)
            }
            if pension.planTaxedIn == .source {
                Picker("Paying country", selection: $pension.sourceCountry) {
                    Text("Not set").tag(CountryCode?.none)
                    ForEach(CountryChoices.common, id: \.self) { code in
                        Text(CountryChoices.name(of: code, locale: locale)).tag(Optional(code))
                    }
                }
            }
        } header: {
            Text("Taxes")
        } footer: {
            Text("A pension taxed where it's paid is entered after that tax.")
        }
        if !fields.isEmpty {
            Section("Details") {
                PlanOptionsForm(fields: fields, options: $pension.options)
            }
        }
        PlanIssuesSection(issues: issues)
    }
}

/// A one-off event: a windfall, an inheritance or an expense, by age or
/// year, with the chance it happens.
struct PlanEventForm: View {
    @Binding var event: PlanEvent
    let issues: [PlanIssue]

    private var whenLabel: String {
        event.planByAge ? "At \(event.planWhen)" : "In \(String(event.planWhen))"
    }

    var body: some View {
        Section("Event") {
            TextField("Name", text: $event.name)
            Picker("Type", selection: $event.planType) {
                ForEach(PlanEventType.allCases, id: \.self) { type in
                    Text(type.title).tag(type)
                }
            }
            PlanNumberRow("Amount", value: $event.planSize)
        }
        Section("When") {
            Picker("Set by", selection: $event.planByAge) {
                Text("Age").tag(true)
                Text("Year").tag(false)
            }
            .pickerStyle(.segmented)
            Stepper(whenLabel, value: $event.planWhen, in: event.planByAge ? 18...110 : 2_000...2_150)
        }
        if event.planType != .expense {
            Section {
                PlanNumberRow("Chance it happens", value: $event.planProbability, kind: .percent, unit: "%")
            } footer: {
                Text("Each simulated future draws whether it happens; the expected path includes it from 50%.")
            }
        }
        PlanIssuesSection(issues: issues)
    }
}

/// A residence period: from which year, which tax system, and its options.
struct PlanResidenceForm: View {
    @Binding var residence: PlanResidence
    let issues: [PlanIssue]

    var body: some View {
        let registry = AppTaxRegistry.standard
        let systems = PlanTaxChoices.allSystems(registry)
        let fields = PlanTaxChoices.systemFields(residence.system, registry: registry)
        Section {
            Stepper("From \(String(residence.from))", value: $residence.from, in: 1_990...2_150)
            Picker("Tax system", selection: $residence.planSystem) {
                ForEach(systems) { system in
                    Text(system.name).tag(system.id)
                }
                if !systems.contains(where: { $0.id == residence.system.rawValue }) {
                    Text(residence.system.rawValue).tag(residence.system.rawValue)
                }
            }
        } header: {
            Text("Tax residence")
        } footer: {
            Text("Residence changes on 1 January; a year split between two countries isn't modelled.")
        }
        if !fields.isEmpty {
            Section("Options") {
                PlanOptionsForm(fields: fields, options: $residence.options)
            }
        }
        PlanIssuesSection(issues: issues)
    }
}

/// A special regime (overlay) and its options.
struct PlanOverlayForm: View {
    @Binding var overlay: PlanOverlay
    let plan: PlanDocument
    let issues: [PlanIssue]
    @Environment(LibraryStore.self) private var library

    var body: some View {
        let registry = AppTaxRegistry.standard
        let overlays = PlanTaxChoices.overlays(for: plan, settings: library.settings, registry: registry)
        let descriptor = registry.regime(overlay.regime.rawValue)?.regime
        Section("Special regime") {
            Picker("Regime", selection: $overlay.planRegime) {
                ForEach(overlays, id: \.id) { regime in
                    Text(regime.name).tag(regime.id)
                }
                if !overlays.contains(where: { $0.id == overlay.regime.rawValue }) {
                    Text(overlay.regime.rawValue).tag(overlay.regime.rawValue)
                }
            }
            if let summary = descriptor?.summary {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if let fields = descriptor?.options, !fields.isEmpty {
            Section("Options") {
                PlanOptionsForm(fields: fields, options: $overlay.options)
            }
        }
        PlanIssuesSection(issues: issues)
    }
}

#Preview("Work phase") {
    PlanItemEditor("Work phase", item: PreviewLibrary.library.plans["base"]!.work[1], onSave: { _ in }) { phase in
        PlanWorkPhaseForm(phase: phase, plan: PreviewLibrary.library.plans["base"]!, issues: [])
    }
    .previewEnvironment()
}

import Glance
import Model
import Planner
import SwiftUI
import WidgetKit

/// The Overview's *Getting started* list (UI.md, "Overview", "Getting
/// started"), in words, free of SwiftUI's views so it can be tested: the
/// first answer, the first import, the home, its mortgage and the pension
/// (while first launch estimated them), the widget, and the first check-in.
struct GettingStartedList: Hashable {
    enum Item: String, Hashable, CaseIterable, Identifiable {
        case answer, importFiles, fillIn, widget, checkIn
        var id: String { rawValue }
    }

    struct Row: Hashable, Identifiable {
        var item: Item
        var title: String
        var isDone: Bool
        var id: Item { item }
    }

    var rows: [Row]

    /// - Parameters:
    ///   - hasAnswer: whether the main plan has an answer.
    ///   - hasWidget: whether one of the app's widgets is added.
    ///   - since: the day first launch created the library on this device.
    init(library: Library, hasAnswer: Bool, hasWidget: Bool, since: CalendarDate, today: CalendarDate,
         locale: Locale = .current) {
        let realAccountHasValues = library.accounts.values.contains { account in
            !account.isStartingEstimate && !library.valuations(for: account.id).isEmpty
        }
        let estimatedHomeOrPension = library.accounts.values.filter {
            $0.isStartingEstimate && [.property, .mortgage, .pensionFund].contains($0.kind)
        }
        let latest = library.latestCheckInDate
        let next = CheckInGlance(last: latest, today: today).next
        var rows = [
            Row(item: .answer, title: "See your first answer", isDone: hasAnswer),
            Row(item: .importFiles, title: "Import your first statement", isDone: realAccountHasValues),
        ]
        if !estimatedHomeOrPension.isEmpty {
            rows.append(Row(item: .fillIn, title: Self.fillInTitle(estimatedHomeOrPension),
                            isDone: estimatedHomeOrPension.allSatisfy(\.isClosed)))
        }
        rows.append(Row(item: .widget, title: Self.widgetTitle, isDone: hasWidget))
        rows.append(Row(item: .checkIn,
                        title: "First check-in · \(AmountFormat.shortDate(next, relativeTo: today, locale: locale))",
                        isDone: latest.map { $0 > since } ?? false))
        self.rows = rows
    }

    var doneCount: Int { rows.filter(\.isDone).count }

    /// Whether every item is done, so the list goes away for good.
    var isDone: Bool { rows.allSatisfy(\.isDone) }

    /// "Fill in your home and pension", or only the one estimated; the
    /// mortgage goes with the home.
    static func fillInTitle(_ estimates: [Account]) -> String {
        let kinds = Set(estimates.map(\.kind))
        if !kinds.contains(.pensionFund) { return "Fill in your home" }
        if kinds == [.pensionFund] { return "Fill in your pension" }
        return "Fill in your home and pension"
    }

    #if os(macOS)
    static let widgetTitle = "Add a widget to your desktop"
    static let widgetHow = "Control-click the desktop, choose Edit Widgets, then find Can I Retire Yet."
    #else
    static let widgetTitle = "Add the Lock Screen widget"
    static let widgetHow = "Touch and hold the Lock Screen, tap Customize, then add Time to retire."
    #endif
}

/// *Getting started* on the Overview, from first launch until it's done
/// (UI.md, "Overview", "Getting started"): a short list with what's done
/// ticked, each item opening what does it. It never counts days or nags,
/// goes away for good once everything is done, and *Hide* puts it away
/// sooner: both clear `AppPreferences.gettingStartedSince`.
struct GettingStartedCard: View {
    @Environment(AppPreferences.self) private var preferences
    @Environment(LibraryStore.self) private var library
    @Environment(PlanStore.self) private var plans
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale
    @State private var hasWidget = false
    @State private var explainsWidget = false

    var body: some View {
        Group {
            if let list, !list.isDone {
                card(list)
            }
        }
        .task(id: list?.isDone) {
            if list?.isDone == true {
                preferences.gettingStartedSince = nil
            } else if list != nil {
                hasWidget = await Self.hasWidget()
            }
        }
    }

    private func card(_ list: GettingStartedList) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.s) {
                ForEach(list.rows) { row in
                    rowView(row)
                }
                Text("Goes away once done.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(.top, Metrics.xs)
            }
        } header: {
            SectionHeader("Getting started", systemImage: "flag") {
                HStack(spacing: Metrics.s) {
                    Text("\(list.doneCount) of \(list.rows.count)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryInk)
                    Button("Hide") { preferences.gettingStartedSince = nil }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private var list: GettingStartedList? {
        guard let since = preferences.gettingStartedSince else { return nil }
        return GettingStartedList(library: library.library, hasAnswer: plans.mainHeadline != nil,
                                  hasWidget: hasWidget, since: since, today: .today(), locale: locale)
    }

    @ViewBuilder
    private func rowView(_ row: GettingStartedList.Row) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Button {
                act(on: row.item)
            } label: {
                HStack(spacing: Metrics.m) {
                    Image(systemName: row.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(row.isDone ? Palette.good : Palette.mutedInk)
                        .accessibilityHidden(true)
                    Text(row.title)
                        .foregroundStyle(row.isDone ? Palette.secondaryInk : Palette.ink)
                        .strikethrough(row.isDone, color: Palette.secondaryInk)
                    Spacer(minLength: Metrics.s)
                    if !row.isDone, row.item != .checkIn, row.item != .fillIn {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.mutedInk)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(row.isDone || row.item == .checkIn || row.item == .fillIn)
            .accessibilityValue(Text(row.isDone ? "Done" : "Not done"))
            if !row.isDone, row.item == .fillIn {
                StarterSpreadsheetButton()
                    .padding(.leading, 32)
            }
            if !row.isDone, row.item == .widget, explainsWidget {
                Text(GettingStartedList.widgetHow)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 32)
            }
        }
    }

    private func act(on item: GettingStartedList.Item) {
        switch item {
        case .answer: navigation.showPlan()
        case .importFiles: navigation.startImport()
        case .widget: explainsWidget.toggle()
        case .fillIn, .checkIn: break
        }
    }

    /// Whether one of the app's widgets is added anywhere.
    private static func hasWidget() async -> Bool {
        let configurations = (try? await WidgetCenter.shared.currentConfigurations()) ?? []
        return !configurations.isEmpty
    }
}

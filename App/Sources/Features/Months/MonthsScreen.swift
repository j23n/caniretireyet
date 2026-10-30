import Model
import SwiftUI
import Tracker

/// *Money In and Out* (UI.md, "Your months"): every cash and savings
/// account's and tax pot's month at each check-in, newest first, with the
/// check-in still to come on top. Each month opens at the balance the month
/// before closed at, and it's done when its lines add up to the bank's
/// balance and every line is checked, or its totals were typed.
///
/// - A month not done offers *Import CSV…*, which reads a bank's statement
///   into lines (``MonthImportSheet``), and *Type Totals…* for a month
///   without a CSV (``MonthTypedTotalsSheet``).
/// - Any other opens its lines (``MonthLinesScreen``), also a past month to
///   fix one: the months after it follow.
/// - A past month shows what came in, was spent and was saved.
struct MonthsScreen: View {
    @Environment(LibraryStore.self) private var library
    @Environment(CheckInStore.self) private var checkIn
    @Environment(\.pageLayout) private var layout
    @State private var showsOlder = false
    @State private var importing: MonthRoute?
    @State private var typing: MonthRoute?
    /// The month whose lines open after its CSV is imported.
    @State private var opened: MonthRoute?

    /// How many months show before *Show Older Months*.
    private static let recentCount = 6

    var body: some View {
        let shown = library.library.moneyMonths(next: nextCheckIn, limit: showsOlder ? nil : Self.recentCount)
        let count = library.library.moneyMonthCount(next: nextCheckIn)
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.xl) {
                Text("One import per account per month. Each month opens at the closing balance before it, and "
                    + "it's done when it adds up and every line is checked.")
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(shown) { month in
                    MoneyMonthSection(month: month, importCSV: { importing = $0 }, typeTotals: { typing = $0 })
                }
                if shown.count < count {
                    Button("Show Older Months") { showsOlder = true }
                }
            }
            .padding(layout.gutter)
            .frame(maxWidth: Metrics.wideReadableWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.page)
        .navigationTitle("Money In and Out")
        .navigationDestination(for: MonthRoute.self) { route in
            MonthLinesScreen(route: route)
        }
        .navigationDestination(for: BrokerageRoute.self) { route in
            BrokerageMonthScreen(route: route)
        }
        .navigationDestination(item: $opened) { route in
            MonthLinesScreen(route: route)
        }
        .sheet(item: $importing) { route in
            MonthImportSheet(route: route) { opened = route }
        }
        .sheet(item: $typing) { route in
            MonthTypedTotalsSheet(route: route)
        }
        .overlay {
            if count == 0 {
                ContentUnavailableView {
                    Label("No months yet", systemImage: "calendar")
                } description: {
                    Text("Add a current or savings account, and its months show here.")
                }
            }
        }
    }

    /// The check-in still to come: the one under way, else the next one due.
    private var nextCheckIn: CalendarDate {
        let status = checkIn.status
        return status.openDate ?? status.nextCheckIn
    }
}

extension MonthRoute: Identifiable {
    var id: String { "\(account) \(through)" }
}

/// One check-in's months: its title, how many are left to do or what came
/// in, was spent and saved, and a row per account.
private struct MoneyMonthSection: View {
    let month: MoneyMonth
    let importCSV: (MonthRoute) -> Void
    let typeTotals: (MonthRoute) -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        let brokerage = library.valuator.brokerageMonths(after: month.from, through: month.through,
                                                         in: library.library)
        let allDone = month.toDo.isEmpty && brokerage.allSatisfy(\.status.isDone)
        VStack(alignment: .leading, spacing: Metrics.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(MonthText.title(month.through, locale: locale))
                    .font(.title3.bold())
                    .privacySensitiveInFeedback()
                Spacer(minLength: Metrics.s)
                Text(MonthText.progress(month, brokerage: brokerage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(allDone ? Palette.good : Palette.secondaryInk)
            }
            if month.isCheckedIn, let totals {
                MonthTotalsStrip(cameIn: totals.income, spent: totals.spent, saved: totals.saved)
            }
            CardRows {
                ForEach(month.accounts) { accountMonth in
                    MonthAccountRow(month: accountMonth,
                                    importCSV: { importCSV(route(accountMonth)) },
                                    typeTotals: { typeTotals(route(accountMonth)) })
                }
                ForEach(brokerage) { brokerageMonth in
                    BrokerageMonthRow(month: brokerageMonth)
                }
            }
        }
    }

    private func route(_ accountMonth: AccountMonth) -> MonthRoute {
        MonthRoute(account: accountMonth.account, through: accountMonth.through)
    }

    /// What came in, was spent and saved over the month, as the savings
    /// rate counts them.
    private var totals: SavingsRate? {
        guard let from = month.from else { return nil }
        return library.valuator.savingsRate(from: from.adding(days: 1), through: month.through)
    }
}

/// *Came in*, *Spent* and *Saved*, side by side.
struct MonthTotalsStrip: View {
    let cameIn: Decimal
    let spent: Decimal
    let saved: Decimal
    var currency: CurrencyCode?

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.m) {
            figure("Came in", cameIn)
            figure("Spent", spent)
            figure("Saved", saved)
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func figure(_ title: String, _ amount: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            AmountText(amount, currency: currency, precision: .cents)
                .font(.body.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// An account's month: its name and where it stands, with *Import CSV…*
/// and *Type Totals…* while it's not done, and opening its lines otherwise.
private struct MonthAccountRow: View {
    let month: AccountMonth
    let importCSV: () -> Void
    let typeTotals: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        if month.status == .notDone {
            HStack(spacing: Metrics.s) {
                label
                Spacer(minLength: Metrics.s)
                if !MonthText.isStillToCome(month.through) {
                    Button("Type Totals…", action: typeTotals)
                        .disabled(!library.canEdit)
                }
                Button("Import CSV…", action: importCSV)
                    .disabled(!library.canEdit)
            }
            .buttonStyle(.borderless)
            .padding(.vertical, Metrics.m)
        } else {
            NavigationLink(value: MonthRoute(account: month.account, through: month.through)) {
                HStack(spacing: Metrics.s) {
                    label
                    Spacer(minLength: Metrics.s)
                    Text(month.status.isDone ? "Open" : isOff ? "Fix" : "Check")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOff ? Palette.warning : Palette.accent)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.mutedInk)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, Metrics.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var isOff: Bool {
        if case .off = month.status { true } else { false }
    }

    private var label: some View {
        let account = library.library.accounts[month.account]
        return VStack(alignment: .leading, spacing: 2) {
            Text(account?.name ?? month.account.rawValue)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .privacySensitiveInFeedback()
            AmountSentenceText(MonthText.status(month, currency: account?.currency ?? .eur, locale: locale))
                .font(.subheadline)
                .foregroundStyle(isOff ? Palette.warning : month.status.isDone ? Palette.good : Palette.secondaryInk)
        }
    }
}

/// A trades account's month: its name and where it stands, opening the
/// brokerage month.
private struct BrokerageMonthRow: View {
    let month: BrokerageMonth

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        let account = library.library.accounts[month.account]
        let isOff = if case .off = month.status { true } else { false }
        NavigationLink(value: BrokerageRoute(account: month.account, from: month.from, through: month.through)) {
            HStack(spacing: Metrics.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account?.name ?? month.account.rawValue)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .privacySensitiveInFeedback()
                    AmountSentenceText(BrokerageText.status(month, currency: account?.currency ?? .eur,
                                                            locale: locale))
                        .font(.subheadline)
                        .foregroundStyle(isOff ? Palette.warning
                            : month.status.isDone ? Palette.good : Palette.secondaryInk)
                }
                Spacer(minLength: Metrics.s)
                Text(month.status.isDone ? "Open" : "Check")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOff ? Palette.warning : Palette.accent)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.mutedInk)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Metrics.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

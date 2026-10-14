import Model
import SwiftUI
import Tracker

/// Trends' *Your last 12 months* (UI.md, "Trends"): the savings rate, what
/// was saved, what came in and what was spent over the 12 months that end at
/// the latest check-in, each with its change against the 12 months before,
/// in four tiles, two by two on iPhone and in a row on the Mac and iPad.
/// Then one sentence against the plan's spending while working. With less
/// than 12 months recorded it covers what there is, titled by where that
/// starts ("Since 30 Jun 2026"). Rates stay with the eye; amounts hide.
struct PlanLastTwelveMonthsCard: View {
    /// `nil` without money in and out in the 12 months.
    let year: PlanLastTwelveMonths?
    /// The plan's spending while working, a year; `nil` when it's past
    /// working.
    var plannedSpending: Decimal?

    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale

    var body: some View {
        Card {
            if let year {
                tiles(year.tiles, currency: year.current.moneyInOut.currency)
                if let words = words(year) {
                    AmountSentenceText(words)
                        .font(PlanProgressFont.text)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No money in and out was recorded in the last 12 months.")
                    .font(PlanProgressFont.text)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SectionHeader(year?.title(locale: locale) ?? "Your last 12 months")
                .privacySensitiveInFeedback(year?.since != nil)
        }
    }

    @ViewBuilder
    private func tiles(_ tiles: [PlanLastTwelveMonths.Tile], currency: CurrencyCode) -> some View {
        if layout.isWide {
            EqualColumns(spacing: Metrics.m, equalHeights: true) {
                ForEach(tiles) { tile in
                    PlanMoneyTile(tile: tile, currency: currency)
                }
            }
        } else {
            VStack(spacing: Metrics.m) {
                EqualColumns(spacing: Metrics.m, equalHeights: true) {
                    ForEach(tiles.prefix(2)) { tile in
                        PlanMoneyTile(tile: tile, currency: currency)
                    }
                }
                EqualColumns(spacing: Metrics.m, equalHeights: true) {
                    ForEach(tiles.dropFirst(2)) { tile in
                        PlanMoneyTile(tile: tile, currency: currency)
                    }
                }
            }
        }
    }

    /// "Against the 12 months before." when the tiles have changes, then
    /// the sentence against the plan's spending while working.
    private func words(_ year: PlanLastTwelveMonths) -> AmountSentence? {
        var words = AmountSentence()
        if year.previous != nil {
            words += "Against the 12 months before."
        }
        if let spending = year.spendingWords(planned: plannedSpending, locale: locale) {
            if !words.isEmpty { words += " " }
            words += spending
        }
        return words.isEmpty ? nil : words
    }
}

/// One tile of *Your last 12 months*: its title, its figure, large, and its
/// change against the 12 months before, in green when it's good news and
/// orange when not, always with its arrow.
struct PlanMoneyTile: View {
    let tile: PlanLastTwelveMonths.Tile
    let currency: CurrencyCode

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.title)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryInk)
            figure
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let change = tile.change {
                Text(verbatim: change.text(currency: currency, locale: locale))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(color(of: change))
                    .privacySensitive(isAmount(change))
                    .privacySensitiveInFeedback()
            }
        }
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.page, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var figure: some View {
        switch tile.figure {
        case .rate(let rate):
            Text(verbatim: rate.map { AmountFormat.percent($0, digits: 0, locale: locale) } ?? "—")
                .monospacedDigit()
                .privacySensitiveInFeedback()
        case .amount(let amount):
            AmountText(amount, currency: currency, tabular: false)
        }
    }

    private func isAmount(_ change: PlanLastTwelveMonths.TileChange) -> Bool {
        if case .amount = change.value { true } else { false }
    }

    private func color(of change: PlanLastTwelveMonths.TileChange) -> Color {
        guard change.direction != 0 else { return Palette.secondaryInk }
        return change.isGood ? Palette.positive : Palette.orangeStroke
    }
}

/// Trends' three cards on money in and out, folded into one while none is
/// recorded (UI.md, "Trends"): what records it, with *Open Accounts*.
struct PlanMoneyInOutEmptyCard: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Card {
            Text("Each check-in records the money that came into and went out of your cash and savings accounts, "
                + "from their second value on. Your savings rate and your money in and out show here from then.")
                .font(PlanProgressFont.text)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if navigation.layout == .tabs || firstMoneyAccount != nil {
                Button {
                    navigation.showAccounts(selecting: firstMoneyAccount)
                } label: {
                    Label("Open Accounts", systemImage: AppSymbol.accounts)
                }
                .buttonStyle(.borderless)
                .font(PlanProgressFont.caption)
            }
        } header: {
            SectionHeader("Money in and out")
        }
    }

    /// The account the sidebar selects, which lists the accounts: the first
    /// open cash or savings account.
    private var firstMoneyAccount: AccountID? {
        library.library.accounts.values.filter { $0.kind.recordsMoneyInOut && !$0.isClosed }.map(\.id).sorted().first
    }
}

#Preview("Your last 12 months") {
    let year = PlanLastTwelveMonths(valuator: PreviewLibrary.valuator, through: PreviewLibrary.latestCheckIn,
                                    recordedSince: "2026-06-30")
    ScrollView {
        VStack(spacing: Metrics.l) {
            PlanLastTwelveMonthsCard(year: year, plannedSpending: 36_000)
                .environment(\.pageLayout, PageLayout())
            PlanLastTwelveMonthsCard(year: year, plannedSpending: 36_000)
                .environment(\.pageLayout, PageLayout(isWide: true))
            PlanLastTwelveMonthsCard(year: year, plannedSpending: 36_000)
                .environment(\.pageLayout, PageLayout())
                .redacted(reason: .privacy)
            PlanMoneyInOutEmptyCard()
        }
        .padding()
    }
    .background(Palette.page)
    .previewEnvironment()
}

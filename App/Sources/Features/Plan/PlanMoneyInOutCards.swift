import Model
import SwiftUI
import Tracker

/// Trends' *Your last 12 months* (UI.md, "Look Back"): the savings rate, what
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

/// *Last 12 months* at the top of Look Back (UI.md, "Look Back"): its title
/// over two small cards, the savings rate with its change against the 12
/// months before ("17%", "2 points more than before", green when it's good
/// news) and what was saved of what came in ("9.200 €", "of 54.000 € that
/// came in"). With less than 12 months recorded, titled by where they
/// start ("Since 30 Jun 2026"). The rest of the 12 months is in *Money in
/// and out* (``PlanLastTwelveMonthsCard``).
struct PlanLastTwelveMonthsFigures: View {
    /// `nil` without money in and out in the 12 months.
    let year: PlanLastTwelveMonths?

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s) {
            Text(year?.since == nil ? "Last 12 months" : (year?.title(locale: locale) ?? ""))
                .textCase(.uppercase)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .padding(.horizontal, Metrics.xs)
                .privacySensitiveInFeedback(year?.since != nil)
                .accessibilityAddTraits(.isHeader)
            if let year {
                let currency = year.current.moneyInOut.currency
                let income = AmountFormat.amount(year.current.income, currency: currency, locale: locale)
                let change = rateChange(year)
                EqualColumns(spacing: Metrics.m, equalHeights: true) {
                    TimelineFigureCard(title: "Savings rate", detail: change.map { AmountSentence($0.words) },
                                       detailColor: change?.color ?? Palette.secondaryInk) {
                        Text(verbatim: year.current.rate.map { AmountFormat.percent($0, digits: 0, locale: locale) }
                            ?? "—")
                            .monospacedDigit()
                            .privacySensitiveInFeedback()
                    }
                    TimelineFigureCard(title: year.current.saved >= 0 ? "Saved" : "Took out",
                                       detail: "of \(amount: income) that came in") {
                        AmountText(abs(year.current.saved), currency: currency, tabular: false)
                    }
                }
            } else {
                Card {
                    Text("No money in and out was recorded in the last 12 months.")
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// "2 points more than before", "Same as before"; `nil` without the 12
    /// months before.
    private func rateChange(_ year: PlanLastTwelveMonths) -> (words: String, color: Color)? {
        guard let change = year.tiles.first?.change, case .points(let points) = change.value else { return nil }
        guard points != 0 else { return ("Same as before", Palette.secondaryInk) }
        let words = "\(Wording.count(abs(points), "point")) \(points > 0 ? "more" : "less") than before"
        return (words, change.isGood ? Palette.positive : Palette.orangeStroke)
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
        FigureTile {
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
/// recorded (UI.md, "Look Back"): what records it, with *Open Accounts*.
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

/// Trends in place of its cards while a savings or investment account's
/// values are typed (UI.md, "Look Back"; `Library.accountsTurningOffTrends`):
/// why it's off, and those accounts, each opening its page.
struct PlanTrendsOffCard: View {
    let accounts: [Account]

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Card {
            Text("Trends is built on the money in and out and the money invested that statements record. "
                + "A typed value is a balance only, so Trends is off while a savings or investment "
                + "account's values are typed.")
                .font(PlanProgressFont.text)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(accounts) { account in
                Button {
                    navigation.showAccount(account.id)
                } label: {
                    Label(account.name, systemImage: AppSymbol.accounts)
                        .privacySensitiveInFeedback()
                }
                .buttonStyle(.borderless)
                .font(PlanProgressFont.text)
            }
            Text("To turn it on, set their Values to From imported files in Edit Account and import their statements.")
                .font(PlanProgressFont.caption)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHeader("Trends is off")
        }
    }
}

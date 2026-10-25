import Model
import SwiftUI
import Tracker

/// *Last 12 months* at the top of Look Back (UI.md, "Look Back"): its title
/// over four tiles, the savings rate, what was saved, what came in and what
/// was spent over the 12 months that end at the latest check-in, each with
/// its change against the 12 months before; two by two on iPhone, in a row
/// on the Mac and iPad. Then one sentence against the plan's spending while
/// working. With less than 12 months recorded it covers what there is,
/// titled by where that starts ("Since 30 Jun 2026").
struct PlanLastTwelveMonthsTiles: View {
    /// `nil` without money in and out in the 12 months.
    let year: PlanLastTwelveMonths?
    /// The plan's spending while working, a year; `nil` when it's past
    /// working.
    var plannedSpending: Decimal?

    @Environment(\.pageLayout) private var layout
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
                if layout.isWide {
                    EqualColumns(spacing: Metrics.m, equalHeights: true) {
                        ForEach(year.tiles) { tile in
                            TwelveMonthsTile(tile: tile, currency: currency)
                                .frame(minHeight: 150)
                        }
                    }
                } else {
                    TileGrid {
                        ForEach(year.tiles) { tile in
                            TwelveMonthsTile(tile: tile, currency: currency)
                                .tileSize(.small)
                        }
                    }
                }
                if let words = year.spendingWords(planned: plannedSpending, locale: locale) {
                    AmountSentenceText(words)
                        .font(PlanProgressFont.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Metrics.xs)
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
}

extension PlanLastTwelveMonths.Tile.Kind {
    /// Lilac for the savings rate, mint for what was saved, sky for what
    /// came in, peach for what was spent.
    var tint: TileTint {
        switch self {
        case .savingsRate: .lilac
        case .saved: .mint
        case .cameIn: .sky
        case .spent: .peach
        }
    }

    /// 🐷 💰 💶 🛒.
    var emoji: String {
        switch self {
        case .savingsRate: "🐷"
        case .saved: "💰"
        case .cameIn: "💶"
        case .spent: "🛒"
        }
    }
}

/// One of the last 12 months' figures as a small tile (UI.md, "Tiles"),
/// tinted by what it is, with its emoji: its title, its figure large, and
/// its change against the 12 months before in a capsule ("▲ 4 points"),
/// green when it's good news and orange when not. The savings rate says
/// what it's of. Rates stay with the eye; amounts hide.
struct TwelveMonthsTile: View {
    let tile: PlanLastTwelveMonths.Tile
    let currency: CurrencyCode
    /// "12 months", beside the title, where the page doesn't say it.
    var period: String?

    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .largeTitle) private var rateSize: CGFloat = 48

    var body: some View {
        ColorTile(tint: tile.kind.tint) {
            HStack(spacing: Metrics.s) {
                TileLabel(tile.title, emoji: tile.kind.emoji)
                if let period {
                    Spacer(minLength: Metrics.xs)
                    Text(period)
                        .font(.caption)
                        .opacity(0.8)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Metrics.s)
            figure
            if tile.kind == .savingsRate {
                Text("of what came in")
                    .font(.caption)
                    .opacity(0.8)
                    .lineLimit(1)
            }
            if let change = tile.change {
                Text(verbatim: change.text(currency: currency, locale: locale))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(color(of: change))
                    .padding(.horizontal, 9)
                    .padding(.vertical, Metrics.xs)
                    .background(Palette.card.opacity(0.75), in: Capsule())
                    .privacySensitive(isAmount(change))
                    .privacySensitiveInFeedback()
                    .padding(.top, Metrics.s)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var figure: some View {
        switch tile.figure {
        case .rate(let rate):
            Text(verbatim: rate.map { AmountFormat.percent($0, digits: 0, locale: locale) } ?? "—")
                .font(.system(size: rateSize, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .privacySensitiveInFeedback()
        case .amount(let amount):
            // Only *Saved* says its sign in its title ("Took out"); what
            // came in and what was spent can be below zero too.
            AmountText(tile.kind == .saved ? abs(amount) : amount, currency: currency, tabular: false)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// Green when the change is good news, orange when not, the tile's ink
    /// when there's none.
    private func color(of change: PlanLastTwelveMonths.TileChange) -> Color {
        guard change.direction != 0 else { return tile.kind.tint.ink }
        return change.isGood ? Palette.positive : Palette.orangeStroke
    }

    private func isAmount(_ change: PlanLastTwelveMonths.TileChange) -> Bool {
        if case .amount = change.value { true } else { false }
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
            PlanLastTwelveMonthsTiles(year: year, plannedSpending: 36_000)
                .environment(\.pageLayout, PageLayout())
            PlanLastTwelveMonthsTiles(year: year, plannedSpending: 36_000)
                .environment(\.pageLayout, PageLayout(isWide: true))
            PlanLastTwelveMonthsTiles(year: year, plannedSpending: 36_000)
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

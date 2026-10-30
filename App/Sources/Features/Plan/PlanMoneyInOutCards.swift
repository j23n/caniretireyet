import Model
import SwiftUI
import Tracker

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
/// its change against the 12 months before in a capsule ("▲ from 27%"),
/// green when it's good news and orange when not. The savings rate says
/// what it's of. Rates stay with the eye; amounts hide.
struct TwelveMonthsTile: View {
    let tile: PlanLastTwelveMonths.Tile
    let currency: CurrencyCode
    /// "last 12 months", under the figure, where the page doesn't say it.
    var period: String?

    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .largeTitle) private var rateSize: CGFloat = 48

    var body: some View {
        ColorTile(tint: tile.kind.tint) {
            TileLabel(tile.title, emoji: tile.kind.emoji)
            Spacer(minLength: Metrics.s)
            figure
            if tile.kind == .savingsRate {
                TileCaption(verbatim: period.map { "of what came in, \($0)" } ?? "of what came in")
            } else if let period {
                TileCaption(verbatim: period)
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
        if case .rate = change.value { false } else { true }
    }
}

/// So far's cards on money in and out, folded into one while none is
/// recorded (UI.md, "So far"): what records it, with *Open Accounts*.
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

    /// The account whose detail opens over *All Accounts* in the sidebar
    /// layout: the first open cash or savings account.
    private var firstMoneyAccount: AccountID? {
        library.library.accounts.values.filter { $0.kind.recordsMoneyInOut && !$0.isClosed }.map(\.id).sorted().first
    }
}

#Preview("No money in and out") {
    ScrollView {
        PlanMoneyInOutEmptyCard()
            .padding()
    }
    .background(Palette.page)
    .previewEnvironment()
}

/// In place of So far's cards on money in and out while a savings or
/// investment account's values are typed (UI.md, "So far";
/// `Library.accountsTurningOffTrends`): why they're off, and those
/// accounts, each opening its page.
struct PlanTrendsOffCard: View {
    let accounts: [Account]

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Card {
            Text("Your savings rate and your money in and out are built on the money in and out and the money "
                + "invested that statements record. A typed value is a balance only, so they're off while a "
                + "savings or investment account's values are typed.")
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
            SectionHeader("Money in and out is off")
        }
    }
}

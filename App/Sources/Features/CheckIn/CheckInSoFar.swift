import Model
import SwiftUI
import Tracker

/// What a check-in's month did so far (UI.md, "Check-in"): what came in,
/// the tax, what was spent and saved, the savings rate, the lost value,
/// and where what was saved went. It counts only the accounts done so far.
struct CheckInSoFar: Hashable, Sendable {
    /// An account and what it saved: money moved in when positive.
    struct Share: Hashable, Sendable, Identifiable {
        var account: AccountID
        var amount: Decimal
        var id: AccountID { account }
    }

    /// Money in before tax, with the pension contributions.
    var cameIn: Decimal = 0
    var tax: Decimal = 0
    var spent: Decimal = 0
    var saved: Decimal = 0
    /// Saved over what came in after tax; `nil` when nothing did.
    var rate: Decimal?
    /// What things that lose value lost, below zero (``Tracker/ValueChange/lost``).
    var lost: Decimal = 0
    /// What net worth's change since the check-in before counts as saved
    /// (``Tracker/Valuator/savedSplit(of:)``): with the one-offs left out,
    /// so the bar's parts add up to the change.
    var netSaved: Decimal = 0
    /// What markets did: price and FX movement, and what nothing explains,
    /// the one-offs among it.
    var markets: Decimal = 0
    /// Where what was saved went: each account's share, largest first,
    /// those with none left out.
    var wentTo: [Share] = []

    /// From the savings rate over the month, and the change since the
    /// check-in before split as Saved counts it (``Tracker/Valuator/savedSplit(of:)``);
    /// zeros without them.
    init(rate savings: SavingsRate?, split: ValueChange?) {
        if let savings {
            cameIn = savings.income + savings.tax
            tax = savings.tax
            spent = savings.spent
            saved = savings.saved
            rate = savings.rate
            wentTo = savings.savedByAccount
                .filter { $0.value != 0 }
                .map { Share(account: $0.key, amount: $0.value) }
                .sorted { ($1.amount, $0.account) < ($0.amount, $1.account) }
        }
        if let split {
            lost = split.lost
            netSaved = split.saved
            markets = split.market + split.other
        }
    }

    /// The total of ``wentTo``.
    var wentToTotal: Decimal { wentTo.reduce(0) { $0 + $1.amount } }

    /// "saved 983,69 € · markets +1.307,15 € · lost value −230,00 €": what
    /// moved net worth, under it; the parts add up to the change.
    func split(currency: CurrencyCode, locale: Locale = .current) -> AmountSentence {
        func amount(_ value: Decimal, signed: Bool) -> String {
            signed ? AmountFormat.signedAmount(value, currency: currency, precision: .cents, locale: locale)
                : AmountFormat.amount(value, currency: currency, precision: .cents, locale: locale)
        }
        var sentence: AmountSentence = "saved \(amount: amount(netSaved, signed: false))"
        sentence += " · markets \(amount: amount(markets, signed: true))"
        if lost != 0 { sentence += " · lost value \(amount: amount(lost, signed: true))" }
        return sentence
    }
}

/// The month so far, beside the groups on the Mac and iPad: what came in,
/// the tax, what was spent and saved, the savings rate; then what lost
/// value; then where what was saved went.
struct CheckInSoFarCard: View {
    let soFar: CheckInSoFar
    let date: CalendarDate

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            Card {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    row("Came in", soFar.cameIn)
                    row("Tax", -soFar.tax, signed: true)
                    row("Spent", -soFar.spent, signed: true)
                    Divider()
                    row("Saved", soFar.saved, bold: true)
                    HStack {
                        Text("Savings rate")
                        Spacer(minLength: Metrics.s)
                        Text(verbatim: soFar.rate.map { AmountFormat.percent($0, digits: 0, locale: locale) } ?? "—")
                            .monospacedDigit()
                            .privacySensitiveInFeedback()
                    }
                    Text("Counts only the accounts done so far.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            } header: {
                SectionHeader("\(AmountFormat.monthName(date, locale: locale)) so far")
                    .privacySensitiveInFeedback()
            }
            if soFar.lost != 0 {
                Card {
                    VStack(alignment: .leading, spacing: Metrics.xs) {
                        row("Lost value", soFar.lost, signed: true)
                        Text("Not spent and not saved: it lowers net worth only.")
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    SectionHeader("Things that lost value")
                }
            }
            if !soFar.wentTo.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Metrics.s) {
                        ForEach(soFar.wentTo) { share in
                            row(library.library.accounts[share.account]?.name ?? share.account.rawValue,
                                share.amount, signed: true, personal: true)
                        }
                        Divider()
                        row("Total", soFar.wentToTotal, signed: true, bold: true)
                    }
                } header: {
                    SectionHeader("Where the saved money went")
                }
            }
        }
    }

    private func row(_ title: String, _ amount: Decimal, signed: Bool = false, bold: Bool = false,
                     personal: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Text(verbatim: title)
                .lineLimit(1)
                .privacySensitiveInFeedback(personal)
            Spacer(minLength: Metrics.s)
            AmountText(amount, currency: library.baseCurrency, precision: .cents, signed: signed)
                .fontWeight(bold ? .semibold : .regular)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The month so far on iPhone, above the groups: what was saved and spent,
/// and how many accounts are done, side by side.
struct CheckInSoFarChips: View {
    let soFar: CheckInSoFar
    let groups: CheckInGroups

    @Environment(LibraryStore.self) private var library

    var body: some View {
        HStack(spacing: Metrics.s) {
            chip("Saved so far") {
                AmountText(soFar.saved, currency: library.baseCurrency, precision: .cents)
            }
            chip("Spent") {
                AmountText(soFar.spent, currency: library.baseCurrency, precision: .cents)
            }
            chip("Done") {
                Text(verbatim: "\(groups.doneCount) of \(groups.count)")
            }
        }
    }

    private func chip(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
            value()
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, Metrics.s)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}

import Glance
import Model
import Planner
import SwiftUI

/// The readiness ring at the leading edge and the answer's words at its
/// right (UI.md, "Can I retire yet?"), as the Overview's answer tile and the
/// plan's answer on iPhone draw them: the headline ("In 15 years"), when
/// ("Age 54 · March 2042"), how the age moved in a year, then `status`. At
/// the largest text sizes the words go under the ring. VoiceOver reads the
/// headline and the ring as one element.
struct RetirementAnswerRow<Status: View>: View {
    let headline: RetirementAnswer
    let words: OverviewAnswerText
    /// "2 years sooner" over "than a year ago, at 56"; the Overview's only.
    var yearMove: OverviewYearMove?
    /// Whether the ring and the words dim: the results are out of date.
    var dims = false
    /// Under the words: the Overview's run status.
    @ViewBuilder var status: Status

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The ring's size, the same at every text size.
    private static var ringSize: CGFloat { 144 }
    private static var ringLineWidth: CGFloat { 12 }

    var body: some View {
        let figure = headline.readinessFigure
        let percent = figure.text { AmountFormat.percent($0, digits: 0, locale: locale) }
        let stack = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.m))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Metrics.l))
        stack {
            if let percent {
                ring(figure, percent: percent)
                    .opacity(dims ? OverviewHeader.dimmedOpacity : 1)
            }
            VStack(alignment: .leading, spacing: Metrics.s) {
                answerWords(nextToRing: percent != nil)
                    .opacity(dims ? OverviewHeader.dimmedOpacity : 1)
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The headline, then when; the headline in largeTitle when there's no
    /// ring beside it.
    private func answerWords(nextToRing: Bool) -> some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(words.title)
                .font(nextToRing ? .title.bold() : .largeTitle.bold())
                .foregroundStyle(Palette.ink)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            if let when = words.whenLine {
                Text(verbatim: when)
                    .foregroundStyle(Palette.ink)
            }
            if let yearMove {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: yearMove.lead)
                        .fontWeight(.semibold)
                        .foregroundStyle(yearMove.isSooner ? Palette.positive : Palette.ink)
                    Text(verbatim: yearMove.detail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
                .padding(.top, Metrics.xs)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .privacySensitiveInFeedback()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [words.spoken, yearMove.map { "\($0.lead) \($0.detail)." }]
            .compactMap(\.self).joined(separator: " ")))
        .accessibilityAddTraits(.isHeader)
    }

    /// The ring, with the percentage and "ready" inside it; it keeps its
    /// size at every text size, and the percentage shrinks to fit.
    private func ring(_ figure: ReadinessFigure, percent: String) -> some View {
        ZStack {
            ReadinessRing(fraction: figure.lappingFill, lineWidth: Self.ringLineWidth, laps: true)
                .privacySensitiveInFeedback()
            VStack(spacing: 0) {
                Text(verbatim: percent)
                    .font(.system(size: 32, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .privacySensitiveInFeedback()
                Text("ready")
                    .foregroundStyle(Palette.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(Self.ringLineWidth + Metrics.s)
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        .accessibilityHidden(true)
    }
}

extension RetirementAnswerRow where Status == EmptyView {
    /// Without a status under the words.
    init(headline: RetirementAnswer, words: OverviewAnswerText, dims: Bool = false) {
        self.init(headline: headline, words: words, dims: dims) { EmptyView() }
    }
}

/// How the age you could retire at moved in a year (UI.md, "Can I retire
/// yet?"): "2 years sooner" over "than a year ago, at 56".
struct OverviewYearMove: Hashable {
    var lead: String
    var detail: String
    var isSooner: Bool
}

/// *On track?* (UI.md, "Can I retire yet?"): where the latest check-in
/// stands against its baseline, as Progress's *Are you on track?* says it
/// ("On plan", "12.400 € ahead of January"), and the coast point line; a
/// tap runs `action`, which opens Progress. While amounts are hidden,
/// VoiceOver reads the standing without the amount. The Overview has it
/// beside *Net worth*, the plan on iPhone beside *What if*.
struct OverviewOnTrackTile: View {
    let onTrack: OverviewOnTrack
    let currency: CurrencyCode
    /// Whether the coast point line dims: the results are out of date.
    var dims = false
    let action: () -> Void

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        Button(action: action) {
            FigureTile(surface: .raised) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                    Text("On track?")
                        .foregroundStyle(Palette.secondaryInk)
                    Spacer(minLength: Metrics.xs)
                    Image(systemName: "chevron.right")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.mutedInk)
                        .accessibilityHidden(true)
                }
                if let position = onTrack.position {
                    let standing = position.standing
                    Text(standing.shortLabel)
                        .font(.title.bold())
                        .foregroundStyle(standing.color)
                        .privacySensitiveInFeedback()
                        .accessibilityLabel(standing.label)
                    OverviewLinePair {
                        HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                            AmountText(abs(position.gap), currency: currency, tabular: false)
                            Text(position.gap >= 0 ? "ahead" : "behind")
                                .privacySensitiveInFeedback()
                        }
                        .foregroundStyle(Palette.ink)
                    } then: {
                        // As Progress's years say it: "ahead of January", "behind January".
                        Text(position.gap >= 0 ? "of \(onTrack.expectation)" : onTrack.expectation)
                            .foregroundStyle(Palette.secondaryInk)
                            .privacySensitiveInFeedback()
                    }
                    .accessibilityHidden(redactionReasons.hidesAmounts)
                } else {
                    Text("Not measured yet")
                        .font(.title.bold())
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let coast = onTrack.coastAge {
                    Text(OverviewOnTrack.coastLine(coast))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(dims ? OverviewHeader.dimmedOpacity : 1)
                        .privacySensitiveInFeedback()
                        .accessibilityLabel(OverviewOnTrack.spokenCoastLine(coast))
                }
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows your progress"))
    }
}

/// Two parts of a tile's line: on one row on the Mac and iPad, where every
/// line fits on one; on iPhone the second under the first, so the tiles'
/// rows line up.
struct OverviewLinePair<First: View, Second: View>: View {
    private let first: First
    private let second: Second

    @Environment(\.pageLayout) private var layout

    init(@ViewBuilder _ first: () -> First, @ViewBuilder then second: () -> Second) {
        self.first = first()
        self.second = second()
    }

    var body: some View {
        if layout.isWide {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
                first
                second
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                first
                second
            }
        }
    }
}

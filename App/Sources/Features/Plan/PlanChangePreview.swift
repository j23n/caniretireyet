import Glance
import Model
import Planner
import SwiftUI

// *With this change* (UI.md, "With this change"): what a change does to the
// plan before it's made, under the form that makes it. The What if sheet
// shows the levers' what-if this way, and every edit sheet its edited copy
// of the plan.

/// How far a change moves your last Monday, in months: "10 months sooner",
/// "A year later", "Same date".
struct PlanDateMove: Hashable {
    /// Months later; below zero when sooner, 0 when it didn't move.
    let months: Int

    /// The move from `base`'s last Monday to `changed`'s; `nil` when either
    /// has no date (you could stop today, or no age works out).
    init?(from base: RetirementAnswer, to changed: RetirementAnswer) {
        guard let before = LastMonday(base), let after = LastMonday(changed) else { return nil }
        months = (after.date.year - before.date.year) * 12 + after.date.month - before.date.month
    }

    var words: String {
        guard months != 0 else { return "Same date" }
        let count = abs(months)
        let span: String = if count % 12 == 0 {
            count == 12 ? "A year" : "\(count / 12) years"
        } else {
            count == 1 ? "A month" : "\(count) months"
        }
        return "\(span) \(months < 0 ? "sooner" : "later")"
    }
}

/// How far a change moved the date, as a small capsule: green when sooner,
/// amber when later, grey when the same.
struct PlanMoveChip: View {
    let move: PlanDateMove

    var body: some View {
        let months = move.months
        let color = months == 0 ? Palette.secondaryInk : months < 0 ? Palette.positive : Palette.warning
        Label {
            Text(verbatim: move.words)
                .lineLimit(1)
        } icon: {
            Image(systemName: months == 0 ? "equal" : months < 0 ? "arrow.left" : "arrow.right")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, Metrics.s)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .fixedSize()
        .privacySensitiveInFeedback()
    }
}

/// *With this change*: your last Monday with the change and how far it
/// moved ("10 months sooner", "Was 27 March 2051, at 63."), the plan's
/// chart with the change, the plan as it is dashed under it, then tiles for
/// how sure, saving and spending a month and what's left at the end, each
/// with how it moved in a capsule. While the change's results are being
/// worked out, the last ones dim; before there are any, a line says so.
struct PlanChangeSummary: View {
    let session: PlanSession
    /// The results with the change; `nil` until they're worked out.
    let changed: PlanResults?
    /// Whether newer results are being worked out.
    var isUpdating = false
    /// Why the change can't be worked out.
    var error: String?
    /// What the chart calls the change: "With the change", "With the levers".
    var label = "With the change"

    @Environment(\.locale) private var locale

    private var base: PlanResults? { session.baseResults }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            if let changed, let plan = session.plan {
                answer(changed)
                    .opacity(isUpdating ? Metrics.dimmedOpacity : 1)
                VStack(alignment: .leading, spacing: Metrics.s) {
                    DecadesLegend(compared: base == nil ? nil : "As it is")
                    DecadesChart(plan: plan, results: changed, compared: base, today: .today(), chartHeight: 210)
                }
                .padding(Metrics.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
                .opacity(isUpdating ? Metrics.dimmedOpacity : 1)
                tiles(changed)
                    .opacity(isUpdating ? Metrics.dimmedOpacity : 1)
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
            } else if isUpdating {
                HStack(spacing: Metrics.s) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Working out what it does…")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                }
            } else {
                Text("Change something above to see what it does to your date.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Your last Monday

    private func answer(_ changed: PlanResults) -> some View {
        let headline = changed.headline
        let move = base.flatMap { PlanDateMove(from: $0.headline, to: headline) }
        return VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                Text("Your last Monday")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                Spacer(minLength: Metrics.s)
                if isUpdating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Updating")
                }
                if let move {
                    PlanMoveChip(move: move)
                }
            }
            Text(verbatim: Self.dateAndAge(headline, locale: locale))
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .privacySensitiveInFeedback()
            if let base {
                Text(verbatim: "Was \(Self.dateAndAge(base.headline, locale: locale)).")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
            }
        }
        .padding(.horizontal, Metrics.xs)
        .accessibilityElement(children: .combine)
    }

    /// "2 June 2050, at 62", "You could stop today", "Not yet".
    static func dateAndAge(_ answer: RetirementAnswer, locale: Locale) -> String {
        if let lastMonday = LastMonday(answer) {
            return "\(GlanceText.lastMonday(lastMonday.date, locale: locale)), at \(lastMonday.age)"
        }
        return answer.canRetireNow ? "You could stop today" : "Not yet"
    }

    // MARK: Tiles

    private func tiles(_ changed: PlanResults) -> some View {
        let focus = changed.details.focus
        let was = base?.details.focus
        let currency = session.currency
        return TileGrid {
            if let success = focus.success {
                PlanChangeTile(tint: .sky, title: "How sure", emoji: "🎯",
                               figure: .text(PlanChangeTile.inTen(success)),
                               caption: "stopping at \(focus.age)",
                               change: was?.success.map { PlanChangeTile.Change.share(from: $0, to: success) })
                    .tileSize(.small)
            }
            if let saving = focus.monthlySaving {
                PlanChangeTile(tint: .mint, title: "Saved a month", emoji: "💰", figure: .amount(saving),
                               caption: "while working", currency: currency,
                               change: was?.monthlySaving.map { PlanChangeTile.Change.amount(saving - $0, good: nil) })
                    .tileSize(.small)
            }
            if let spending = changed.headline.sustainableSpending {
                let age = changed.details.sustainableSpendingAge ?? changed.headline.targetAge
                let before = base?.headline.sustainableSpending
                PlanChangeTile(tint: .butter, title: "You could spend", emoji: "🛍️", figure: .amount(spending / 12),
                               caption: "a month" + (age.map { " from \($0)" } ?? ""), currency: currency,
                               change: before.map { PlanChangeTile.Change.amount((spending - $0) / 12, good: true) })
                    .tileSize(.small)
            }
            if let left = focus.medianAtEnd {
                let leftAmount = Decimal(wholeNumber: left)
                PlanChangeTile(tint: .peach, title: "Left at \(changed.details.endAge)", emoji: "🏁",
                               figure: .amount(leftAmount), caption: "typically", currency: currency,
                               change: was?.medianAtEnd.map {
                                   PlanChangeTile.Change.amount(leftAmount - Decimal(wholeNumber: $0), good: true)
                               })
                    .tileSize(.small)
            }
        }
    }
}

/// One of *With this change*'s tiles: its title, its figure with the
/// change, a few words under it, and how it moved from the plan as it is
/// in a capsule ("▲ 500 €", "Same as now"), green when that's good news,
/// orange when not, the tile's ink when it's neither.
struct PlanChangeTile: View {
    enum Figure {
        case text(String)
        case amount(Decimal)
    }

    enum Change {
        /// A share of futures, from one to the other.
        case share(from: Double, to: Double)
        /// An amount more, or less below zero; `good` says whether more is
        /// good news (`nil`: neither).
        case amount(Decimal, good: Bool?)
    }

    let tint: TileTint
    let title: String
    let emoji: String
    let figure: Figure
    let caption: String
    var currency: CurrencyCode = .eur
    let change: Change?

    @Environment(\.locale) private var locale

    var body: some View {
        ColorTile(tint: tint) {
            TileLabel(title, emoji: emoji)
            Spacer(minLength: Metrics.s)
            switch figure {
            case .text(let text):
                Text(verbatim: text)
                    .font(.title2.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .privacySensitiveInFeedback()
            case .amount(let amount):
                AmountText(amount, currency: currency, tabular: false)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            TileCaption(verbatim: caption)
                .privacySensitiveInFeedback()
            if let change {
                pill(change)
                    .padding(.top, Metrics.s)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func pill(_ change: Change) -> some View {
        let (text, direction, good, isAmount) = words(change)
        let color: Color = direction == 0 || good == nil ? tint.ink
            : (direction > 0) == good ? Palette.positive : Palette.orangeStroke
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, Metrics.xs)
            .background(Palette.card.opacity(0.75), in: Capsule())
            .privacySensitive(isAmount && direction != 0)
            .privacySensitiveInFeedback()
    }

    /// The capsule's words, which way it moved, whether more is good, and
    /// whether the words are an amount.
    private func words(_ change: Change) -> (String, Int, Bool?, Bool) {
        switch change {
        case .share(let from, let to):
            let before = Self.tenths(from)
            let after = Self.tenths(to)
            guard before != after else { return ("Same as now", 0, true, false) }
            return ("\(after > before ? "▲" : "▼") from \(Self.inTen(from))", after > before ? 1 : -1, true, false)
        case .amount(let difference, let good):
            let whole = difference.rounded(scale: 0)
            guard whole != 0 else { return ("Same as now", 0, good, false) }
            let amount = AmountFormat.amount(abs(whole), currency: currency, locale: locale)
            return ("\(whole > 0 ? "▲" : "▼") \(amount)", whole > 0 ? 1 : -1, good, true)
        }
    }

    /// A share of futures in tenths, as the plan says it: 9 for 0.9.
    static func tenths(_ share: Double) -> Int {
        PlanTimelineText.tenths(share)
    }

    /// "9 in 10".
    static func inTen(_ share: Double) -> String {
        "\(tenths(share)) in 10"
    }
}

// MARK: - Working out a change

/// Works out *With this change* for an edited copy of the plan: the
/// results the engine kept for it at once, else, once the form rests for a
/// moment, a quick estimate, then every run. A newer copy replaces the
/// one being worked out. The plan as it is needs nothing worked out.
struct PlanChangePreview: View {
    let session: PlanSession
    /// The plan with the change; `nil`, or the plan as it is, before a change.
    let candidate: PlanDocument?

    @State private var results: PlanResults?
    @State private var resultsFor: PlanDocument?
    @State private var isUpdating = false
    @State private var error: String?

    /// How long the form rests before the change is worked out.
    private static let delay: Duration = .milliseconds(400)

    private var changed: PlanDocument? {
        guard let candidate, candidate != session.plan else { return nil }
        return candidate
    }

    var body: some View {
        PlanChangeSummary(session: session, changed: changed == nil ? nil : results,
                          isUpdating: isUpdating || (changed != nil && resultsFor != changed),
                          error: changed == nil ? nil : error)
            .task(id: changed) { await workOut(changed) }
    }

    private func workOut(_ document: PlanDocument?) async {
        error = nil
        guard let document else {
            isUpdating = false
            return
        }
        if let kept = await session.cachedPreview(document) {
            guard !Task.isCancelled else { return }
            results = kept
            resultsFor = document
            isUpdating = kept.mode != .full
            if kept.mode == .full { return }
        }
        isUpdating = true
        try? await Task.sleep(for: Self.delay)
        guard !Task.isCancelled else { return }
        do {
            if resultsFor != document {
                let quick = try await session.preview(document, mode: .fast)
                guard !Task.isCancelled else { return }
                results = quick
                resultsFor = document
            }
            let full = try await session.preview(document, mode: .full)
            guard !Task.isCancelled else { return }
            results = full
            resultsFor = document
            isUpdating = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            self.error = PlanStore.describe(error)
            isUpdating = false
        }
    }
}

import Model
import SwiftUI
import Tracker

// Views the check-in's iPhone list and Mac table share: the number field,
// the state indicator, amounts without a currency, the progress bar, the
// legend, the date panel and the banners at the top.

// MARK: - Number field

/// A field for an amount or a quantity (UI.md, "Keyboard"). It shows the
/// draft's value in the locale's format, reads what's typed with
/// `AmountInput` (`1.234,56` and `1234.56` both work) and reports each
/// change as it's typed, so totals and states follow along. When it loses
/// the focus, its text is tidied to the value that was recorded.
///
/// The focus state belongs to the list or table; it passes `isFocused` in,
/// so the field notices when it gains or loses the focus.
struct CheckInNumberField: View {
    let field: CheckInField
    let focus: FocusState<CheckInField?>.Binding
    let isFocused: Bool
    let value: Decimal?
    let style: CheckInFieldFormat.Style
    /// Shown while the field is empty, e.g. the estimated amount paid.
    let prompt: String
    /// What VoiceOver reads, e.g. "Conto Fineco, value".
    let label: String
    /// Whether clearing the field reports `nil` (new money, paid, cash)
    /// rather than being ignored (a balance, a quantity).
    let allowsEmpty: Bool
    /// Bumped by the ± key: the focused field flips its sign.
    let signToggle: Int
    let onSubmit: () -> Void
    let onChange: (Decimal?) -> Void

    @Environment(\.locale) private var locale
    @State private var text: String

    init(_ field: CheckInField, focus: FocusState<CheckInField?>.Binding, isFocused: Bool, value: Decimal?,
         style: CheckInFieldFormat.Style = .amount, prompt: String = "", label: String, allowsEmpty: Bool = false,
         signToggle: Int = 0, onSubmit: @escaping () -> Void = {}, onChange: @escaping (Decimal?) -> Void) {
        self.field = field
        self.focus = focus
        self.isFocused = isFocused
        self.value = value
        self.style = style
        self.prompt = prompt
        self.label = label
        self.allowsEmpty = allowsEmpty
        self.signToggle = signToggle
        self.onSubmit = onSubmit
        self.onChange = onChange
        _text = State(initialValue: CheckInFieldFormat.text(for: value, style: style, locale: .current))
    }

    var body: some View {
        TextField(label, text: $text, prompt: Text(prompt))
            .labelsHidden()
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .privacySensitive()
            .autocorrectionDisabled()
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            .focused(focus, equals: field)
            .onSubmit { onSubmit() }
            .onAppear {
                if !isFocused { text = formatted(value) }
            }
            .onChange(of: value) { _, newValue in
                if !isFocused { text = formatted(newValue) }
            }
            .onChange(of: isFocused) { _, nowFocused in
                if !nowFocused { text = formatted(value) }
            }
            .onChange(of: text) { _, newText in
                if isFocused { report(newText) }
            }
            .onChange(of: signToggle) { _, _ in
                if isFocused { text = CheckInFieldFormat.toggledSign(text, style: style) }
            }
    }

    private func formatted(_ value: Decimal?) -> String {
        CheckInFieldFormat.text(for: value, style: style, locale: locale)
    }

    /// Reports what's typed: an amount (for a debt, signed as a balance),
    /// `nil` for an empty field if that means something, and nothing while
    /// it can't be read (e.g. just "-").
    private func report(_ newText: String) {
        if newText.trimmingCharacters(in: .whitespaces).isEmpty {
            if allowsEmpty { onChange(nil) }
            return
        }
        guard let amount = CheckInFieldFormat.value(from: newText, style: style, locale: locale) else { return }
        onChange(amount)
    }
}

/// A row's note (the Mac table's Note column). Editing it doesn't change
/// the row's state.
struct CheckInNoteField: View {
    let field: CheckInField
    let focus: FocusState<CheckInField?>.Binding
    let isFocused: Bool
    let note: String?
    let label: String
    let onSubmit: () -> Void
    let onChange: (String) -> Void

    @State private var text: String

    init(_ field: CheckInField, focus: FocusState<CheckInField?>.Binding, isFocused: Bool, note: String?,
         label: String, onSubmit: @escaping () -> Void = {}, onChange: @escaping (String) -> Void) {
        self.field = field
        self.focus = focus
        self.isFocused = isFocused
        self.note = note
        self.label = label
        self.onSubmit = onSubmit
        self.onChange = onChange
        _text = State(initialValue: note ?? "")
    }

    var body: some View {
        TextField(label, text: $text, prompt: Text(verbatim: ""))
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused(focus, equals: field)
            .onSubmit { onSubmit() }
            .onChange(of: note) { _, newNote in
                if !isFocused { text = newNote ?? "" }
            }
            .onChange(of: text) { _, newText in
                if isFocused { onChange(newText.trimmingCharacters(in: .whitespaces)) }
            }
    }
}

extension View {
    /// The look of a check-in field: a light fill, and a ring in the accent
    /// colour while it has the focus.
    func checkInFieldBox(isFocused: Bool, height: CGFloat = 36) -> some View {
        padding(.horizontal, Metrics.s)
            .frame(height: height)
            .background(Palette.mutedInk.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: isFocused ? 2 : 0)
            }
    }
}

// MARK: - State

/// A row's state: ● updated, ✓ unchanged, ○ not reviewed yet, – skipped.
struct CheckInStateIndicator: View {
    let state: CheckInRowState
    var size: CGFloat = 22

    var body: some View {
        Group {
            switch state {
            case .updated:
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 12, height: 12)
            case .unchanged:
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.secondaryInk)
            case .notReviewed:
                Circle()
                    .strokeBorder(Palette.mutedInk, lineWidth: 1.75)
                    .frame(width: 11, height: 11)
            case .skipped:
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.mutedInk)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: CheckInWording.stateName(state)))
    }
}

/// "● Updated  ✓ Unchanged  ○ Not reviewed yet".
struct CheckInLegend: View {
    var body: some View {
        HStack(spacing: Metrics.l) {
            ForEach([CheckInRowState.updated, .unchanged, .notReviewed], id: \.self) { state in
                HStack(spacing: Metrics.xs) {
                    CheckInStateIndicator(state: state, size: 16)
                        .accessibilityHidden(true)
                    Text(verbatim: CheckInWording.stateName(state))
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(Palette.secondaryInk)
        .accessibilityElement(children: .combine)
    }
}

/// How many accounts are reviewed, as a thin bar.
struct CheckInProgressBar: View {
    let reviewed: Int
    let total: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.accent.opacity(0.2))
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "\(reviewed) of \(total) accounts reviewed"))
    }

    private var fraction: CGFloat {
        total > 0 ? CGFloat(reviewed) / CGFloat(total) : 0
    }
}

// MARK: - Amounts

/// An amount without its currency, for table cells and captions:
/// `4.210,55`, or `+1.450,00` when signed. Tabular figures; `•••••` while
/// amounts are hidden.
struct CheckInPlainAmount: View {
    let amount: Decimal?
    var signed = false
    /// Shown when there's no amount.
    var placeholder = "—"

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    init(_ amount: Decimal?, signed: Bool = false, placeholder: String = "—") {
        self.amount = amount
        self.signed = signed
        self.placeholder = placeholder
    }

    var body: some View {
        Text(verbatim: text)
            .monospacedDigit()
            .privacySensitive()
            .accessibilityLabel(hidesAmounts && amount != nil ? Text("Amount hidden") : Text(verbatim: text))
    }

    private var text: String {
        guard let amount else { return placeholder }
        return hidesAmounts ? AmountFormat.hidden : CheckInFieldFormat.plain(amount, signed: signed, locale: locale)
    }
}

/// A change without its currency, with an arrow and colour as well as the
/// sign (UI.md, "Changes"): `▲ +3.652,35`, `▼ −310,20`.
struct CheckInPlainDelta: View {
    let amount: Decimal?

    @Environment(\.hidesAmounts) private var hidesAmounts
    @Environment(\.locale) private var locale

    init(_ amount: Decimal?) {
        self.amount = amount
    }

    var body: some View {
        Text(verbatim: text)
            .monospacedDigit()
            .foregroundStyle(color)
            .privacySensitive()
            .accessibilityLabel(Text(verbatim: spoken))
    }

    private var number: String {
        guard let amount else { return "—" }
        return hidesAmounts ? AmountFormat.hidden : CheckInFieldFormat.plain(amount, signed: true, locale: locale)
    }

    private var text: String {
        guard let amount, amount != 0 else { return number }
        return (amount > 0 ? "▲ " : "▼ ") + number
    }

    private var spoken: String {
        guard let amount else { return "No change" }
        let direction = amount > 0 ? "up" : amount < 0 ? "down" : "unchanged"
        return hidesAmounts ? "\(direction), amount hidden" : "\(direction) \(number)"
    }

    private var color: Color {
        guard let amount, amount != 0 else { return Palette.secondaryInk }
        return amount > 0 ? Palette.positive : Palette.negative
    }
}

/// A change in quantity: `▲ +10,5` or `▼ −5`, with colour.
struct CheckInQuantityChange: View {
    let change: Decimal

    @Environment(\.locale) private var locale

    init(_ change: Decimal) {
        self.change = change
    }

    var body: some View {
        Text(verbatim: text)
            .monospacedDigit()
            .fontWeight(.medium)
            .foregroundStyle(change > 0 ? Palette.positive : change < 0 ? Palette.negative : Palette.secondaryInk)
    }

    private var text: String {
        let number = CheckInWording.quantityChange(change, locale: locale)
        if change > 0 { return "▲ " + number }
        if change < 0 { return "▼ " + number }
        return number
    }
}

// MARK: - Prices

/// The icon of the price status: a spinner while fetching, a check when
/// everything is in, a warning when something needs typing in.
struct CheckInPriceStatusIcon: View {
    let kind: CheckInPriceStatus.Kind

    var body: some View {
        switch kind {
        case .fetching:
            ProgressView()
                .controlSize(.small)
        case .updated:
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Palette.good)
                .accessibilityHidden(true)
        case .needsAttention:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.warning)
                .accessibilityHidden(true)
        case .notFetched:
            Image(systemName: "clock")
                .foregroundStyle(Palette.mutedInk)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Date

/// Picks the check-in's date (UI.md, "Date": today by default, the end of
/// last month in a month's first days). The new date is applied when the
/// panel closes: what was entered is kept, and prices are fetched again.
struct CheckInDatePanel: View {
    let date: CalendarDate
    let suggested: CalendarDate
    let onPick: (CalendarDate) -> Void

    /// The latest date offered: today, or the check-in's date if it's later.
    private let latest: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var selection: Date

    init(date: CalendarDate, suggested: CalendarDate, onPick: @escaping (CalendarDate) -> Void) {
        self.date = date
        self.suggested = suggested
        self.onPick = onPick
        latest = max(Date(), date.dateValue)
        _selection = State(initialValue: date.dateValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            HStack {
                Text("Check-in date")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .keyboardShortcut(.defaultAction)
            }
            DatePicker("Check-in date", selection: $selection, in: ...latest, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            if picked != suggested {
                Button {
                    selection = suggested.dateValue
                } label: {
                    Text(verbatim: "Use \(AmountFormat.longDate(suggested, locale: locale)) (suggested)")
                }
            }
            Text("Values are as of the end of this day. What you've entered is kept; prices are fetched again for the new date. "
                + "An earlier date fills in your history.")
                .font(.footnote)
                .foregroundStyle(Palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Metrics.l)
        .frame(minWidth: 300, idealWidth: 340)
        .onDisappear {
            if picked != date { onPick(picked) }
        }
    }

    private var picked: CalendarDate {
        CalendarDate(selection, in: .current)
    }
}

// MARK: - Banners

/// The notes at the top of the check-in: the library's own state, a failed
/// save, a check-in being resumed or updating a saved one, a past check-in
/// (no answer is recorded for it), and hidden amounts.
struct CheckInBanners: View {
    let draft: CheckInDraft
    let session: CheckInSession

    @Environment(LibraryStore.self) private var library
    @Environment(PrivacySettings.self) private var privacy
    @Environment(\.locale) private var locale

    init(draft: CheckInDraft, session: CheckInSession) {
        self.draft = draft
        self.session = session
    }

    var body: some View {
        VStack(spacing: Metrics.s) {
            LibraryStatusBanners()
            if let error = session.saveError {
                StatusBanner(.error, "Couldn't save the check-in", message: error, actionTitle: "Dismiss") {
                    session.saveError = nil
                }
            }
            if let note = CheckInWording.conflictNote(draft, in: library.library, locale: locale) {
                StatusBanner(.warning, "Saved on another device", message: note, actionTitle: "Choose") {
                    session.page = .review
                }
            }
            if let resumed = session.resumedDate {
                StatusBanner(
                    .info, "Continuing your check-in",
                    message: "Started for \(AmountFormat.longDate(resumed, locale: locale)). What you entered is still here.",
                    actionTitle: "Start over") {
                        session.showsStartOverDialog = true
                    }
            }
            if let note = CheckInWording.existingCheckInNote(on: draft.date, in: library.library, locale: locale) {
                StatusBanner(.info, "Updating a saved check-in", message: note)
            }
            if let note = CheckInWording.pastCheckInNote(on: draft.date, in: library.library, locale: locale) {
                StatusBanner(.info, "A past check-in", message: note)
            }
            if privacy.hidesAmounts {
                StatusBanner(.info, "Amounts are hidden", message: "The fields still show what you type.",
                             actionTitle: "Show amounts") {
                    privacy.toggleHidesAmounts()
                }
            }
        }
    }
}

#Preview("Check-in pieces") {
    VStack(alignment: .leading, spacing: Metrics.m) {
        CheckInLegend()
        HStack {
            CheckInPlainAmount(PreviewLibrary.d("4210.55"))
            CheckInPlainDelta(PreviewLibrary.d("-310.2"))
            CheckInPlainDelta(PreviewLibrary.d("3652.35"))
            CheckInQuantityChange(PreviewLibrary.d("10.5"))
        }
        CheckInProgressBar(reviewed: 7, total: 9)
            .frame(width: 112)
        ForEach([CheckInPriceStatus.Kind.fetching, .updated, .needsAttention, .notFetched], id: \.self) { kind in
            CheckInPriceStatusIcon(kind: kind)
        }
        CheckInDatePanel(date: CheckInPreviewData.date, suggested: "2026-10-31") { _ in }
    }
    .padding()
    .previewEnvironment()
}

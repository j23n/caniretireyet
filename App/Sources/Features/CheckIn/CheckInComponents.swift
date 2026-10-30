import Glance
import Model
import SwiftUI
import Tracker

// Pieces of the check-in page: the price status icon, the date panel and the
// page while saving.

// MARK: - Prices

/// The icon of the price status: a spinner while fetching, a check when
/// everything is in, a warning when a price is missing.
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

// MARK: - The date, moved

/// How the date moved since the check-in before, as a chip under it: "A
/// year sooner" in the accent, "2 years later" in the warning color, "The
/// same date" in gray, each with an arrow.
struct CheckInMoveChip: View {
    let move: LastMondayMove

    var body: some View {
        let color = move.years == 0 ? Palette.secondaryInk : move.isSooner ? Palette.accent : Palette.warning
        Label {
            Text(verbatim: CheckInAnswer.move(move))
        } icon: {
            Image(systemName: move.years == 0 ? "equal" : move.isSooner ? "arrow.left" : "arrow.right")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color)
        .lineLimit(1)
        .padding(.horizontal, Metrics.m)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
        .privacySensitiveInFeedback()
    }
}

// MARK: - Date

/// Picks the check-in's date (UI.md, "Date"): the suggested date, today,
/// the latest saved check-ins to edit (one whose money is off says by how
/// much), or any other day in the calendar, which adds a check-in between
/// two you have. Tapping a date picks it; *Done* takes the calendar's.
/// Prices are fetched again for the new date. On iPhone it lists four
/// dates, and the calendar is behind *Another Date…*.
struct CheckInDatePanel: View {
    let date: CalendarDate
    let suggested: CalendarDate
    let onPick: (CalendarDate) -> Void

    /// The latest date offered: today, or the check-in's date if it's later.
    private let latest: Date

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @State private var selection: Date
    @State private var applies = false

    init(date: CalendarDate, suggested: CalendarDate, onPick: @escaping (CalendarDate) -> Void) {
        self.date = date
        self.suggested = suggested
        self.onPick = onPick
        latest = max(Date(), date.dateValue, suggested.dateValue)
        _selection = State(initialValue: date.dateValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(options) { option in
                        Button {
                            selection = option.date.dateValue
                            apply()
                        } label: {
                            optionRow(option)
                        }
                        .buttonStyle(.plain)
                    }
                    if !layout.isWide {
                        NavigationLink("Another Date…") {
                            Form {
                                calendar
                            }
                            .formStyle(.grouped)
                            .navigationTitle("Another Date")
                            .toolbar { toolbar }
                        }
                    }
                }
                if layout.isWide {
                    calendar
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Check-in date")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
        }
        .frame(minWidth: 360, idealWidth: 400, minHeight: 600)
        .onDisappear {
            if applies, picked != date { onPick(picked) }
        }
    }

    /// The dates offered: four on iPhone, the one picked among them.
    private var options: [CheckInDateOption] {
        let all = CheckInDateMenu.options(suggested: suggested, today: .today(), library: library.library)
        return layout.isWide ? all : CheckInDateMenu.compactOptions(all, picked: picked)
    }

    /// Any other day, in a calendar, with what picking one does.
    private var calendar: some View {
        Section {
            DatePicker("Check-in date", selection: $selection, in: ...latest, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .personalControl()
        } footer: {
            Text("Any other day adds a check-in between two you have: your lines stay where they are, and "
                + "balances are compared there too. Values are as of the end of the day, and prices are "
                + "fetched again for it.")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { apply() }
                .fontWeight(.semibold)
                .keyboardShortcut(.defaultAction)
        }
    }

    /// A date, the line under it, and a check for the one picked, or
    /// *Edit* or *Fix* for a saved check-in.
    private func optionRow(_ option: CheckInDateOption) -> some View {
        HStack(spacing: Metrics.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: AmountFormat.mediumDate(option.date, locale: locale))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                AmountSentenceText(CheckInDateMenu.hint(option, locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(option.isOff ? Palette.warning : Palette.secondaryInk)
            }
            .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.s)
            if picked == option.date {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .accessibilityLabel("Picked")
            } else if option.isSaved {
                Text(option.isOff ? "Fix" : "Edit")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(option.isOff ? Palette.warning : Palette.accent)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func apply() {
        applies = true
        dismiss()
    }

    private var picked: CalendarDate {
        CalendarDate(selection, in: .current)
    }
}

// MARK: - Saving

/// What shows while the check-in saves: "Saving…". The plan's answer is
/// worked out afterwards, with its progress on the confirmation.
struct CheckInSavingView: View {
    var body: some View {
        VStack(spacing: Metrics.m) {
            ProgressView()
            Text("Saving…")
                .foregroundStyle(Palette.secondaryInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.page)
    }
}

#Preview("Check-in pieces") {
    VStack(alignment: .leading, spacing: Metrics.m) {
        HStack {
            ForEach([CheckInPriceStatus.Kind.fetching, .updated, .needsAttention, .notFetched], id: \.self) { kind in
                CheckInPriceStatusIcon(kind: kind)
            }
        }
        CheckInDatePanel(date: CheckInPreviewData.date, suggested: "2026-10-31") { _ in }
    }
    .padding()
    .previewEnvironment()
}

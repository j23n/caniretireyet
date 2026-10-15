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

// MARK: - Date

/// Picks the check-in's date (UI.md, "Date": today by default, the end of
/// last month in a month's first days). The new date is applied when the
/// panel closes, and prices are fetched again.
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
                .personalControl()
            if picked != suggested {
                Button {
                    selection = suggested.dateValue
                } label: {
                    Text(verbatim: "Use \(AmountFormat.longDate(suggested, locale: locale)) (suggested)")
                }
                .personalControl()
            }
            Text("Values are as of the end of this day, and prices are fetched again for the new date. "
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

import Model
import Prices
import SwiftUI
import Tracker

// PLACEHOLDER — Check-in feature engineer: replace this screen's content
// (UI.md, "Check-in": the one-page flow, price list, keyboard, review,
// confirmation, and the Mac table). Keep the name `CheckInScreen` and
// `init()`: it's the full-screen cover on iPhone (inside a NavigationStack)
// and the Check-in page on Mac and iPad. Close it with
// `navigation.finishCheckIn()`, which works in both. All state lives in
// `CheckInStore`; this placeholder already edits balances and saves.

/// The monthly check-in.
struct CheckInScreen: View {
    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @State private var saveError: String?
    @State private var confirmation: CheckInSaveResult?

    init() {}

    var body: some View {
        Group {
            if let draft = checkIn.draft {
                form(for: draft)
            } else if let confirmation {
                ConfirmationView(result: confirmation) { navigation.finishCheckIn() }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Check-in")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    checkIn.persistNow()
                    navigation.finishCheckIn()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(checkIn.draft == nil || !library.canEdit)
            }
        }
        .onAppear {
            if checkIn.draft == nil && confirmation == nil { checkIn.begin() }
        }
    }

    private func form(for draft: CheckInDraft) -> some View {
        Form {
            Section {
                LabeledContent("Date", value: AmountFormat.longDate(draft.date))
                LabeledContent("Prices and FX") {
                    if checkIn.isFetchingPrices {
                        ProgressView()
                    } else if let list = checkIn.priceList {
                        Text(list.isComplete ? "Updated (\(list.entries.count))" : "\(list.failures.count) couldn't be fetched")
                    } else {
                        Text("\(draft.prices.count) prices")
                    }
                }
            }
            ForEach(AccountGroup.allCases, id: \.self) { group in
                let rows = draft.rows.filter { library.account($0.account)?.group == group }
                if !rows.isEmpty {
                    Section(group.description) {
                        ForEach(rows) { row in
                            CheckInRowView(row: row)
                        }
                    }
                }
            }
            Section {
                HStack {
                    Text("\(draft.reviewedCount) of \(draft.rows.count) reviewed")
                    Spacer()
                    Button("Mark rest unchanged") { checkIn.markRestUnchanged() }
                        .disabled(draft.isReadyToSave)
                }
                if let review = checkIn.review {
                    LabeledContent("New net worth") { AmountText(review.netWorth.total) }
                    if let change = review.change {
                        LabeledContent("Change") { DeltaText(change.total.change) }
                    }
                }
                if let saveError {
                    Text(saveError).foregroundStyle(Palette.critical)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func save() {
        Task {
            do {
                confirmation = try await checkIn.save()
                saveError = nil
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}

/// One account in the check-in: previous value, a field for the new
/// balance, and its state (● updated, ✓ unchanged, ○ not reviewed).
private struct CheckInRowView: View {
    let row: CheckInRow
    @Environment(CheckInStore.self) private var checkIn
    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @State private var text = ""

    var body: some View {
        let account = library.account(row.account)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account?.name ?? row.account.rawValue)
                if let previous = row.previous?.balance {
                    HStack(spacing: 4) {
                        Text("was")
                        AmountText(previous, currency: account?.currency, precision: .cents)
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer()
            if row.mode == .balance {
                TextField("Balance", text: $text)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 140)
                    .onSubmit(commit)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
            } else {
                Text("\(row.positions.count) position\(row.positions.count == 1 ? "" : "s")")
                    .foregroundStyle(Palette.secondaryInk)
            }
            Button {
                checkIn.updateRow(row.account) { $0.markUnchanged() }
            } label: {
                Image(systemName: stateSymbol)
                    .foregroundStyle(row.state == .notReviewed ? Palette.mutedInk : Palette.accent)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(stateLabel)
        }
        .onAppear {
            if let balance = row.balance { text = AmountInput.text(for: balance, maxDigits: 2, locale: locale) }
        }
    }

    private func commit() {
        guard let amount = AmountInput.decimal(from: text, locale: locale) else { return }
        checkIn.updateRow(row.account) { $0.setBalance(amount) }
    }

    private var stateSymbol: String {
        switch row.state {
        case .updated: "circle.fill"
        case .unchanged: "checkmark.circle"
        case .notReviewed: "circle"
        case .skipped: "minus.circle"
        }
    }

    private var stateLabel: String {
        switch row.state {
        case .updated: "Updated"
        case .unchanged: "Unchanged"
        case .notReviewed: "Not reviewed; mark unchanged"
        case .skipped: "Skipped"
        }
    }
}

/// The monthly moment: "Saved · Net worth 312.480 € (▲ 4.210)", then the answer.
private struct ConfirmationView: View {
    let result: CheckInSaveResult
    let done: () -> Void

    var body: some View {
        VStack(spacing: Metrics.l) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(Palette.good)
                .accessibilityHidden(true)
            HStack(spacing: Metrics.xs) {
                Text("Saved · Net worth")
                AmountText(result.netWorth)
                if let change = result.change {
                    DeltaText(change.change)
                }
            }
            if let headline = result.headline {
                Text(answer(headline))
                    .multilineTextAlignment(.center)
            }
            Button("Done", action: done)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func answer(_ headline: PlanHeadline) -> String {
        if headline.canRetireNow { return "Can I retire yet? Yes." }
        if let age = headline.earliestAge { return "Can I retire yet? Not yet: earliest at \(age)." }
        return "Can I retire yet? Not yet."
    }
}

#Preview("Check-in") {
    NavigationStack {
        CheckInScreen()
    }
    .previewEnvironment()
}

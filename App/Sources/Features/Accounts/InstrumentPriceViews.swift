import Model
import Prices
import SwiftUI
import Tracker

// The views that show and change instrument prices outside a check-in
// (UI.md, "Instruments"): the latest price in lists, *Update Prices*'
// status and results, and *Set Price…*.

// MARK: - Latest price

/// An instrument's latest saved price and its date, "(typed in)" when it
/// wasn't fetched although the instrument has a price source, and a small
/// clock when it's older than the staleness threshold.
struct InstrumentLatestPriceLabel: View {
    let latest: InstrumentLatestPrice?
    let threshold: Int

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: Metrics.xs) {
            if let latest {
                Text(verbatim: latest.text(locale: locale))
                    .monospacedDigit()
                if let note = latest.sourceNote {
                    Text(verbatim: "(\(note))")
                        .foregroundStyle(Palette.secondaryInk)
                }
                if latest.isStale {
                    InstrumentStaleMark(threshold: threshold)
                }
            } else {
                Text("No price yet")
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
    }
}

/// A small clock: the latest price is older than the staleness threshold.
struct InstrumentStaleMark: View {
    let threshold: Int

    var body: some View {
        Image(systemName: "clock")
            .foregroundStyle(Palette.warning)
            .help(InstrumentLatestPrice.staleHelp(threshold: threshold))
            .accessibilityLabel(InstrumentLatestPrice.staleHelp(threshold: threshold))
    }
}

// MARK: - Update status

/// *Update Prices*' status above the instruments: progress while it runs,
/// then what happened, with Details and a close button.
struct InstrumentPriceUpdateBanner: View {
    let run: InstrumentPriceUpdate
    let isRunning: Bool
    let showDetails: () -> Void
    let close: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: Metrics.m) {
            icon
                .frame(width: 22)
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(verbatim: run.summary)
                    .font(.subheadline.weight(.medium))
                if isRunning {
                    let progress = run.progress
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                } else if let finishedAt = run.finishedAt {
                    Text(verbatim: "Saved at " + CheckInPriceList.time(finishedAt, locale: locale))
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            Spacer(minLength: Metrics.s)
            Button("Details", action: showDetails)
                .buttonStyle(.borderless)
            if !isRunning {
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityLabel("Close")
                .help("Close")
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if isRunning {
            ProgressView()
                .controlSize(.small)
        } else if run.needsAttention {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Palette.warning)
                .accessibilityLabel("Needs a look")
        } else {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Palette.good)
                .accessibilityLabel("Done")
        }
    }
}

// MARK: - Update results

/// Every line of the latest *Update Prices*: each instrument's new price,
/// or why it failed or wasn't saved, and the exchange rates. A price typed
/// in by hand for the day is kept; its row's Update replaces it. A failed
/// row can be tried again.
struct InstrumentPriceUpdateSheet: View {
    let updater: InstrumentPriceUpdater

    @Environment(LibraryStore.self) private var library
    @Environment(PriceStore.self) private var prices
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if let run = updater.run {
                content(run)
            } else {
                ContentUnavailableView("No price update", systemImage: "arrow.clockwise")
            }
        }
        .sheetTitle("Price Update") { dismiss() }
    }

    private func content(_ run: InstrumentPriceUpdate) -> some View {
        let canAct = updater.canUpdate(library: library, prices: prices)
        return Form {
            Section {
                HStack(spacing: Metrics.s) {
                    if updater.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(verbatim: run.summary)
                }
            } footer: {
                if let skipped = run.skippedText {
                    Text(verbatim: skipped + " Use Update Price on an instrument's row to fetch it anyway.")
                }
            }
            if !run.instruments.isEmpty {
                Section {
                    ForEach(run.instruments) { line in
                        InstrumentPriceUpdateRow(line: line, canAct: canAct) { replacingTyped in
                            update(line, replacingTyped: replacingTyped)
                        }
                    }
                } header: {
                    Text(verbatim: "Instruments · \(AmountFormat.shortDate(run.date, locale: locale))")
                } footer: {
                    Text("Prices are saved for today, from the latest close or quote. "
                        + "Only symbols, currencies and dates leave this device.")
                }
            }
            if !run.rates.isEmpty {
                Section {
                    ForEach(run.rates) { line in
                        InstrumentPriceUpdateRow(line: line, canAct: false) { _ in }
                    }
                } header: {
                    Text("Exchange rates")
                } footer: {
                    Text(verbatim: "How much of each currency 1 \(run.baseCurrency.rawValue) buys, from the ECB.")
                }
            }
            if !run.indices.isEmpty {
                Section {
                    ForEach(run.indices) { line in
                        InstrumentPriceUpdateRow(line: line, canAct: false) { _ in }
                    }
                } header: {
                    Text("Inflation")
                } footer: {
                    Text("Consumer prices for the months the library is missing, from Eurostat, the BLS or the ONS.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func update(_ line: InstrumentPriceUpdate.Line, replacingTyped: Bool) {
        guard let id = line.instrument else { return }
        Task {
            await updater.update(id, replacingTyped: replacingTyped, library: library, prices: prices)
        }
    }
}

/// One instrument or rate of a price update: its status, the fetched value,
/// what happened, and Update or Try Again when they apply.
private struct InstrumentPriceUpdateRow: View {
    let line: InstrumentPriceUpdate.Line
    let canAct: Bool
    let update: (_ replacingTyped: Bool) -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            statusIcon
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: line.title)
                    .fontWeight(.medium)
                if let source = line.sourceLine {
                    Text(verbatim: source)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                Text(verbatim: line.detail(locale: locale))
                    .font(.footnote)
                    .foregroundStyle(line.failure == nil ? Palette.secondaryInk : Palette.critical)
                    .fixedSize(horizontal: false, vertical: true)
                if line.isInstrument && canAct {
                    if line.status == .keptTyped {
                        Button("Update") { update(true) }
                            .buttonStyle(.borderless)
                            .font(.footnote.weight(.semibold))
                    } else if line.failure != nil {
                        Button("Try Again") { update(false) }
                            .buttonStyle(.borderless)
                            .font(.footnote.weight(.semibold))
                    }
                }
            }
            Spacer(minLength: Metrics.s)
            if let value = line.valueText(locale: locale) {
                Text(verbatim: value)
                    .monospacedDigit()
                    .foregroundStyle(line.status == .keptTyped ? Palette.secondaryInk : Palette.ink)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch line.status {
        case .fetching, .fetched:
            ProgressView()
                .controlSize(.small)
        case .updated:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.good)
                .accessibilityLabel("Updated")
        case .unchanged:
            Image(systemName: "equal.circle")
                .foregroundStyle(Palette.secondaryInk)
                .accessibilityLabel("Unchanged")
        case .keptTyped:
            Image(systemName: "hand.raised")
                .foregroundStyle(Palette.warning)
                .accessibilityLabel("Typed in, kept")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.critical)
                .accessibilityLabel("Failed")
        }
    }
}

// MARK: - Set price

/// *Set Price…*: a price typed in by hand for a date (today by default),
/// per the instrument's unit, in its currency unless another is chosen.
/// It's saved as a `manual` price record, replacing any price saved for
/// that date; *Update Prices* keeps it. For an instrument not
/// saved yet, `onSet` gets the record instead, to save with it.
struct InstrumentSetPriceSheet: View {
    /// `nil` for an instrument that isn't saved yet.
    let instrumentID: InstrumentID?
    let name: String
    let currency: CurrencyCode
    let unit: InstrumentUnit
    /// Receives the record instead of saving it to the library.
    let onSet: ((PriceRecord) -> Void)?

    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var form: InstrumentPriceForm
    @State private var showsProblems = false
    @State private var errorMessage: String?

    /// `date` is the day it starts on: today by default, or a past date that
    /// has no price (*Fill In Past Prices*).
    init(instrumentID: InstrumentID?, name: String, currency: CurrencyCode, unit: InstrumentUnit,
         date: CalendarDate? = nil, onSet: ((PriceRecord) -> Void)? = nil) {
        self.instrumentID = instrumentID
        self.name = name
        self.currency = currency
        self.unit = unit
        self.onSet = onSet
        _form = State(initialValue: InstrumentPriceForm(currency: currency, date: date ?? .today()))
    }

    var body: some View {
        let problems = form.problems(locale: locale)
        Form {
            Section {
                DatePicker("Date", selection: $form.pickedDate, in: ...Date(), displayedComponents: .date)
                AccountsNumberField(title: "Price", text: $form.amount, prompt: prompt,
                                    suffix: "per " + InstrumentForm.name(of: unit), allowsNegative: false)
                Picker("Currency", selection: $form.currency) {
                    ForEach(currencies, id: \.self) { code in
                        Text(CurrencyChoices.name(of: code, locale: locale)).tag(code)
                    }
                }
            } header: {
                Text(verbatim: name)
            } footer: {
                Text("Net worth uses the latest price on or before each date. "
                    + "Update Prices won't replace a price you type in.")
            }
            if let note = replacementNote {
                Section {
                    Label(note, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
            if showsProblems {
                AccountsProblemsSection(problems: problems)
            }
            AccountsErrorSection(message: errorMessage)
        }
        .formStyle(.grouped)
        .navigationTitle("Set Price")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!library.canEdit)
            }
        }
    }

    /// The latest saved price as the field's prompt, e.g. "138,42".
    private var prompt: String {
        guard let instrumentID,
              let latest = library.valuator.prices.latest(for: instrumentID, onOrBefore: form.date)
        else { return "0" }
        return AmountInput.text(for: latest.price, locale: locale)
    }

    private var replacementNote: String? {
        guard let instrumentID else { return nil }
        let saved = library.library.price(PriceKey(instrument: instrumentID, date: form.date))
        return InstrumentPriceForm.replacementNote(saved, locale: locale)
    }

    private var currencies: [CurrencyCode] {
        CurrencyChoices.common.including(form.currency).including(currency)
    }

    private func save() {
        guard let record = form.record(for: instrumentID ?? "new", locale: locale) else {
            showsProblems = true
            return
        }
        if let onSet {
            onSet(record)
            dismiss()
            return
        }
        do {
            try library.upsert(prices: [record])
            dismiss()
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}

/// A saved instrument to set a price for, and the day *Set Price…* starts
/// on (`nil`: today).
struct SetPriceTarget: Identifiable, Hashable {
    var instrument: InstrumentID
    var date: CalendarDate?

    var id: Self { self }
}

extension View {
    /// Presents *Set Price…* for the target's instrument as a sheet.
    func setPriceSheet(item: Binding<SetPriceTarget?>) -> some View {
        sheet(item: item) { target in
            NavigationStack {
                SetPriceTargetSheet(target: target)
            }
            #if os(macOS)
            .frame(minWidth: 380, idealWidth: 440, minHeight: 320, idealHeight: 380)
            #endif
        }
    }
}

/// *Set Price…* for the target's instrument as the library has it, or that
/// it no longer exists.
private struct SetPriceTargetSheet: View {
    let target: SetPriceTarget

    @Environment(LibraryStore.self) private var library

    var body: some View {
        if let instrument = library.library.instruments[target.instrument] {
            InstrumentSetPriceSheet(instrumentID: instrument.id, name: instrument.name, currency: instrument.currency,
                                    unit: instrument.unit, date: target.date)
        } else {
            ContentUnavailableView("This instrument no longer exists", systemImage: "questionmark.folder")
        }
    }
}

#Preview("Set price") {
    NavigationStack {
        InstrumentSetPriceSheet(instrumentID: "vwce", name: "Vanguard FTSE All-World", currency: "EUR", unit: .share)
    }
    .previewEnvironment()
}

#Preview("Update banner") {
    let run = InstrumentPriceUpdate(plan: InstrumentPriceUpdatePlan(library: PreviewLibrary.library, on: .today()))
    List {
        InstrumentPriceUpdateBanner(run: run, isRunning: true, showDetails: {}, close: {})
    }
    .previewEnvironment()
}

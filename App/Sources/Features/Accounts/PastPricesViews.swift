import Model
import Prices
import SwiftUI

// *Fill In Past Prices…* (UI.md, "Instruments" and "Adding history"): what
// the library is missing on past dates, a fill with progress and a result
// per instrument, and the note under a chart that uses old prices. The
// logic is in PastPriceFilling.swift.

/// Lists every past date without a price, rate or inflation figure, fetches
/// them (*Fill In*) with progress, and shows what each instrument got and
/// from where. Prices that can't be fetched (no price source, or no history
/// anywhere) are listed with their dates, each with *Set Price…* for a date
/// and *Choose a Price Source*. Shown from the Instruments toolbar, the
/// import's Done step, and the notes under charts.
struct PastPricesSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PriceStore.self) private var prices
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var filler = PastPriceFiller()
    @State private var settingPrice: SetPriceTarget?
    @State private var editingInstrument: InstrumentEditTarget?

    init() {}

    var body: some View {
        content
            .navigationTitle("Fill In Past Prices")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(closeTitle) { dismiss() }
                        .disabled(filler.isRunning)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if filler.phase != .done {
                        Button("Fill In") { run() }
                            .disabled(!filler.canRun(library: library, prices: prices))
                    }
                }
            }
            .interactiveDismissDisabled(filler.isRunning)
            .onAppear { filler.prepare(library: library, prices: prices) }
            .onChange(of: library.revision) { _, _ in
                filler.prepare(library: library, prices: prices)
            }
            .setPriceSheet(item: $settingPrice)
            .instrumentEditorSheet(item: $editingInstrument)
    }

    private var closeTitle: String {
        filler.phase == .done ? "Done" : "Cancel"
    }

    @ViewBuilder
    private var content: some View {
        if let plan = filler.plan {
            if plan.isEmpty && filler.phase == .ready {
                ContentUnavailableView {
                    Label("Nothing to fill in", systemImage: "checkmark.circle")
                } description: {
                    Text("Every past value has a price for its date, and the exchange rates and inflation figures "
                        + "are there.")
                }
            } else {
                form(plan)
            }
        } else {
            ProgressView()
        }
    }

    private func form(_ plan: PastPricePlan) -> some View {
        Form {
            Section {
                statusRow
            } footer: {
                Text("Fills in every date a position is valued on without a price for that day: each value, and "
                    + "the month ends it carries over to. Each instrument's dates are one request. Nothing saved "
                    + "is replaced, whether typed in, imported or fetched. Only symbols, currencies and dates leave "
                    + "this device.")
            }
            let fetched = plan.fetchedLines
            if !fetched.isEmpty {
                Section {
                    ForEach(fetched) { line in
                        lineRow(line)
                    }
                } header: {
                    Text("To fetch")
                } footer: {
                    Text("Past prices of gold, silver, platinum and palladium come from their futures on Yahoo "
                        + "Finance (GC=F for gold), which trade within about 1% of the spot price. Crypto older "
                        + "than CoinGecko's free year comes from Yahoo Finance's pairs, such as BTC-EUR.")
                }
            }
            let manual = plan.manualLines
            if !manual.isEmpty {
                Section {
                    ForEach(manual) { line in
                        lineRow(line)
                    }
                } header: {
                    Text("To type in")
                } footer: {
                    Text("These have no price source. Set a price for a date, or choose a source to fetch them "
                        + "from and fill in again.")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch filler.phase {
        case .ready:
            Text(verbatim: filler.statusText ?? "")
            if !prices.canFetch {
                Text("Prices aren't fetched here.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
            }
        case .fetching(let progress):
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(verbatim: filler.statusText ?? "")
                ProgressView(value: progress.fraction)
            }
        case .saving:
            HStack(spacing: Metrics.s) {
                ProgressView()
                    .controlSize(.small)
                Text("Saving…")
            }
        case .done:
            Label {
                Text(verbatim: filler.statusText ?? "")
            } icon: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Palette.good)
            }
            Button("Check Again") { filler.reset(library: library, prices: prices) }
                .disabled(!library.canEdit)
        case .failed(let reason):
            Label {
                Text(verbatim: reason)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Palette.critical)
            }
        }
    }

    /// A line, and for an instrument with dates still missing (typed in, or
    /// not found anywhere), *Set Price…* per date and the price source.
    private func lineRow(_ line: PastPriceLine) -> some View {
        let missing = stillMissing(line)
        let offersActions = line.canBeTypedIn && !missing.isEmpty && !filler.isRunning
            && (line.kind == .manual || line.result != nil)
        let sourceTitle: String = line.kind == .manual ? "Choose a Price Source" : "Change Price Source"
        return VStack(alignment: .leading, spacing: Metrics.xs) {
            PastPriceLineRow(line: line, missingCount: missing.count)
            if offersActions, let id = line.instrument {
                HStack(spacing: Metrics.m) {
                    Menu("Set Price…") {
                        ForEach(Array(missing.reversed().prefix(60)), id: \.self) { date in
                            Button(AmountFormat.mediumDate(date, locale: locale)) {
                                settingPrice = SetPriceTarget(instrument: id, date: date)
                            }
                        }
                    }
                    .fixedSize()
                    Button(sourceTitle) {
                        editingInstrument = InstrumentEditTarget(instrument: id)
                    }
                }
                .buttonStyle(.borderless)
                .font(.footnote.weight(.semibold))
                .disabled(!library.canEdit)
                .padding(.leading, 28)
            }
        }
    }

    /// The line's missing dates that still have no price saved (one may
    /// have been typed in since).
    private func stillMissing(_ line: PastPriceLine) -> [CalendarDate] {
        guard let id = line.instrument else { return line.missing }
        return line.missing.filter { library.library.savedPrice(of: id, on: $0) == nil }
    }

    private func run() {
        Task { await filler.run(library: library, prices: prices) }
    }
}

/// One line of *Fill In Past Prices*: what it is, its dates, where the
/// values come from (or came from, and why some didn't), and how many.
private struct PastPriceLineRow: View {
    let line: PastPriceLine
    /// The dates still without a value.
    let missingCount: Int

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            icon
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: line.title)
                    .fontWeight(.medium)
                Text(verbatim: PastPriceText.dates(line.dates, locale: locale))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                if let source = sourceText {
                    Text(verbatim: source)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                }
                if missingCount > 0, let reason = line.result?.reason {
                    Text(verbatim: reason)
                        .font(.footnote)
                        .foregroundStyle(isFailure ? Palette.critical : Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Metrics.s)
            Text(verbatim: PastPriceText.status(of: line))
                .monospacedDigit()
                .foregroundStyle(Palette.secondaryInk)
        }
        .padding(.vertical, 2)
    }

    /// Where the values came from after a fill, else where they'll come from.
    private var sourceText: String? {
        line.result.flatMap { PastPriceText.sources($0.sources, locale: locale) } ?? line.source
    }

    /// Whether a fetch failed (an inflation month not out yet isn't one).
    private var isFailure: Bool {
        guard line.kind != .index, let status = line.result?.status else { return false }
        return status == .notFilled || status == .partlyFilled
    }

    @ViewBuilder
    private var icon: some View {
        switch line.result?.status {
        case nil:
            Image(systemName: line.kind == .manual || line.kind == .unknown ? "hand.raised" : "clock.arrow.circlepath")
                .foregroundStyle(Palette.secondaryInk)
        case .filled?:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.good)
                .accessibilityLabel("Filled")
        case .partlyFilled?:
            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(Palette.warning)
                .accessibilityLabel("Partly filled")
        case .notFilled?:
            Image(systemName: line.kind == .index ? "clock" : "exclamationmark.triangle.fill")
                .foregroundStyle(line.kind == .index ? Palette.secondaryInk : Palette.critical)
                .accessibilityLabel("Not filled")
        case .manual?, .unknownInstrument?:
            Image(systemName: "hand.raised")
                .foregroundStyle(Palette.warning)
                .accessibilityLabel("To type in")
        }
    }
}

/// The note under a chart whose values use a price more than 31 days older
/// than their date (``OldPriceNote``), or can't be worked out because a
/// price or rate is missing (``MissingValueNote``, with a warning
/// `systemImage`), with *Fill In Past Prices…* (left out without `fill`,
/// when there's nothing it could fetch).
struct OldPriceNoteView: View {
    let text: String
    var systemImage = "clock.badge.exclamationmark"
    var fill: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.xs) {
            Label {
                Text(verbatim: text)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondaryInk)
            if let fill {
                Button("Fill In Past Prices…", action: fill)
                    .buttonStyle(.borderless)
                    .font(.footnote.weight(.semibold))
            }
        }
    }
}

extension View {
    /// Presents *Fill In Past Prices* as a sheet.
    func pastPricesSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            NavigationStack {
                PastPricesSheet()
            }
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, minHeight: 480, idealHeight: 640)
            #endif
        }
    }
}

#Preview("Fill in past prices") {
    NavigationStack {
        PastPricesSheet()
    }
    .previewEnvironment()
}

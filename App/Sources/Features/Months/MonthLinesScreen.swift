import Importer
import Model
import SwiftUI
import Tracker

/// One account's month (UI.md, "A month's lines"): the balance it opens at,
/// every line since, and the balance they close at against the bank's.
/// Lines the import suggested show their class dashed with a question
/// mark until they're checked. Selecting a line edits it: what it is, the
/// account money moved to, a note, or removing it, such as a line listed
/// twice (``MonthLineEditor``), in a column beside the lines on the Mac
/// and iPad, in a sheet on iPhone.
///
/// - *Does it add up?*: the opening balance, money in and out, the closing
///   balance they lead to, and the bank's, typed here when the statement
///   had none.
/// - The month's totals: what came in, one-offs, tax, spent, saved, moved.
/// - *The months after it*: each opens at the balance before it, so fixing
///   this month shows at once whether the next still adds up.
/// - *Add Line* adds one the statement missed; *Accept Suggestions* checks
///   every line still a suggestion as it is.
struct MonthLinesScreen: View {
    let route: MonthRoute

    @Environment(LibraryStore.self) private var library
    @Environment(CheckInStore.self) private var checkIn
    @Environment(\.pageLayout) private var layout
    @Environment(\.locale) private var locale
    @State private var filter = MonthLineFilter.all
    @State private var selection: BankLineKey?
    @State private var editing: MonthLineSelection?
    @State private var addsLine = false
    @State private var importsCSV = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let month, let account {
                content(month, account: account)
            } else {
                ContentUnavailableView("No such month", systemImage: "calendar")
            }
        }
        .background(Palette.page)
        .personalNavigationTitle(title, hidden: "Month")
        .toolbar { toolbar }
        .sheet(isPresented: $addsLine) {
            if let month, let account {
                MonthAddLineSheet(month: month, account: account)
            }
        }
        .sheet(isPresented: $importsCSV) {
            MonthImportSheet(route: route)
        }
        .sheet(item: $editing) { selection in
            if let month, let account, let line = month.lines.first(where: { $0.key == selection.key }) {
                NavigationStack {
                    ScrollView {
                        MonthLineEditor(line: line, month: month, account: account) { editing = nil }
                            .padding(Metrics.l)
                    }
                    .background(Palette.page)
                    .navigationTitle("Line")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { editing = nil }
                        }
                    }
                }
            }
        }
        .alert("Something went wrong", isPresented: showsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var month: AccountMonth? {
        library.library.accountMonth(of: route.account, through: route.through)
    }

    private var account: Account? { library.library.accounts[route.account] }

    private var title: String {
        "\(account?.name ?? route.account.rawValue) · \(MonthText.title(route.through, locale: locale))"
    }

    private var showsError: Binding<Bool> {
        Binding { errorMessage != nil } set: { if !$0 { errorMessage = nil } }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                addsLine = true
            } label: {
                Label("Add Line", systemImage: "plus")
            }
            .disabled(!library.canEdit)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button {
                importsCSV = true
            } label: {
                Label("Import CSV…", systemImage: AppSymbol.importData)
            }
            .disabled(!library.canEdit)
        }
    }

    // MARK: Layout

    @ViewBuilder
    private func content(_ month: AccountMonth, account: Account) -> some View {
        if layout.isWide {
            HStack(alignment: .top, spacing: Metrics.l) {
                ScrollView {
                    linesColumn(month, account: account)
                        .padding(layout.gutter)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.m) {
                        if let selection, let line = month.lines.first(where: { $0.key == selection }) {
                            Card {
                                MonthLineEditor(line: line, month: month, account: account) { self.selection = nil }
                                    .id(line)
                            }
                        }
                        sideCards(month, account: account)
                    }
                    .padding(.vertical, layout.gutter)
                    .padding(.trailing, layout.gutter)
                }
                .frame(width: 360)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.m) {
                    let totals = MonthTotals(month)
                    MonthTotalsStrip(cameIn: totals.cameIn + totals.interest, spent: totals.spent,
                                     saved: totals.saved, currency: account.currency)
                    MonthAddsUpBanner(month: month, currency: account.currency)
                    linesColumn(month, account: account)
                    sideCards(month, account: account)
                }
                .padding(layout.gutter)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar(month)
            }
        }
    }

    private func linesColumn(_ month: AccountMonth, account: Account) -> some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            if layout.isWide {
                HStack {
                    Text(subtitle(month))
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                    Spacer(minLength: Metrics.s)
                    acceptButton(month)
                }
            }
            filterPicker(month)
            MonthLinesList(month: month, account: account, filter: filter, selection: selection) { line in
                if layout.isWide {
                    selection = line.key
                } else {
                    editing = MonthLineSelection(key: line.key)
                }
            }
        }
    }

    @ViewBuilder
    private func sideCards(_ month: AccountMonth, account: Account) -> some View {
        MonthAddsUpCard(month: month, currency: account.currency)
        MonthTotalsCard(month: month, account: account)
        MonthsAfterCard(month: month, next: checkIn.status.openDate ?? checkIn.status.nextCheckIn,
                        currency: account.currency)
    }

    private func subtitle(_ month: AccountMonth) -> String {
        let from = month.from.map { AmountFormat.shortDate($0.adding(days: 1), locale: locale) }
        let through = AmountFormat.shortDate(month.through, locale: locale)
        let span = from.map { "\($0) – \(through)" } ?? "Through \(through)"
        return "\(span) · \(Wording.count(month.lines.count, "line"))"
    }

    private func filterPicker(_ month: AccountMonth) -> some View {
        Picker("Show", selection: $filter) {
            ForEach(MonthLineFilter.allCases) { filter in
                Text(filterTitle(filter, month: month)).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func filterTitle(_ filter: MonthLineFilter, month: AccountMonth) -> String {
        let count = month.lines.filter(filter.shows).count
        return filter == .all || count == 0 ? filter.title : "\(filter.title) \(count)"
    }

    private func acceptButton(_ month: AccountMonth) -> some View {
        Button("Accept \(Wording.count(month.linesToCheck, "Suggestion"))") {
            acceptSuggestions(month)
        }
        .buttonStyle(.borderedProminent)
        .disabled(month.linesToCheck == 0 || !library.canEdit)
    }

    private func bottomBar(_ month: AccountMonth) -> some View {
        HStack(spacing: Metrics.s) {
            Button {
                addsLine = true
            } label: {
                Label("Add Line", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!library.canEdit)
            acceptButton(month)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .padding(.horizontal, layout.gutter)
        .padding(.vertical, Metrics.s)
        .background(.bar)
    }

    // MARK: Editing

    /// Confirms every line still a suggestion, as the import suggested it.
    private func acceptSuggestions(_ month: AccountMonth) {
        let lines = month.lines.filter { !$0.isConfirmed && !$0.isRemoved }.map { line in
            var confirmed = line
            confirmed.confirmed = true
            return confirmed
        }
        do {
            try library.update { $0.save(lines) }
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}

/// A line opened in the editor's sheet on iPhone.
struct MonthLineSelection: Identifiable, Hashable {
    var key: BankLineKey
    var id: String { key.description }
}

// MARK: - The lines

/// The month's lines between its opening and closing balances, as the
/// filter shows them. Selecting one edits it.
private struct MonthLinesList: View {
    let month: AccountMonth
    let account: Account
    let filter: MonthLineFilter
    let selection: BankLineKey?
    let select: (BankLine) -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        let lines = month.lines.filter(filter.shows)
        VStack(alignment: .leading, spacing: 0) {
            balanceRow("Opening balance", detail: openingDetail, amount: month.opening)
            Divider()
            ForEach(lines, id: \.key) { line in
                Button {
                    select(line)
                } label: {
                    MonthLineRow(line: line, currency: account.currency, otherName: otherName(line))
                        .background(line.key == selection ? Palette.accent.opacity(0.12) : Color.clear)
                }
                .buttonStyle(.plain)
                Divider()
            }
            if lines.isEmpty {
                Text(month.lines.isEmpty ? "No lines yet. Import the month's CSV, or add a line."
                    : "No line here.")
                    .foregroundStyle(Palette.secondaryInk)
                    .padding(Metrics.m)
                Divider()
            }
            balanceRow("Closing balance from these lines", detail: nil, amount: month.stretch.expectedClosing)
        }
        .cardSurface()
    }

    private var openingDetail: String {
        guard let from = month.from else { return "Before the account's first value" }
        return "The balance on \(AmountFormat.shortDate(from, locale: locale)), carried over"
    }

    private func otherName(_ line: BankLine) -> String? {
        line.otherAccount.map { library.library.accounts[$0]?.name ?? $0.rawValue }
    }

    private func balanceRow(_ title: String, detail: String?, amount: Decimal?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                }
            }
            Spacer(minLength: Metrics.s)
            if let amount {
                AmountText(amount, currency: account.currency, precision: .cents)
                    .font(.body.weight(.semibold))
            } else {
                Text("—")
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .padding(Metrics.m)
    }
}

/// One line: the bank's text, its class, its date and its amount.
private struct MonthLineRow: View {
    let line: BankLine
    let currency: CurrencyCode
    let otherName: String?

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(line.text.isEmpty ? "No text" : line.text)
                    .strikethrough(line.isRemoved)
                    .foregroundStyle(line.isRemoved ? Palette.secondaryInk : Palette.ink)
                    .lineLimit(2)
                    .privacySensitiveInFeedback()
                HStack(spacing: Metrics.s) {
                    MonthLineChip(line: line, otherName: otherName)
                    Text(AmountFormat.shortDate(line.date, locale: locale))
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                    if let note = line.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryInk)
                            .lineLimit(1)
                            .privacySensitiveInFeedback()
                    }
                }
            }
            Spacer(minLength: Metrics.s)
            AmountText(line.amount, currency: currency, precision: .cents, signed: true)
                .foregroundStyle(line.amount > 0 ? Palette.positive : Palette.ink)
                .opacity(line.isRemoved ? 0.5 : 1)
        }
        .padding(Metrics.m)
        .contentShape(Rectangle())
    }
}

/// A line's class: filled once it's checked, dashed with a question mark
/// while it's the import's suggestion, "Removed" for a removed line.
struct MonthLineChip: View {
    let line: BankLine
    let otherName: String?

    var body: some View {
        let isSuggestion = !line.isConfirmed && !line.isRemoved
        let name = line.isRemoved ? "Removed" : MonthText.kind(line.statementClass, other: otherName)
        let shape = Capsule(style: .continuous)
        Text(isSuggestion ? "\(name)?" : name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, Metrics.s)
            .padding(.vertical, 2)
            .background(isSuggestion ? Color.clear : color.opacity(0.14), in: shape)
            .overlay {
                if isSuggestion {
                    shape.strokeBorder(color.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            .privacySensitiveInFeedback(line.statementClass == .transfer && otherName != nil)
    }

    private var color: Color {
        if line.isRemoved { return Palette.secondaryInk }
        switch line.statementClass {
        case .income, .interest: return Palette.positive
        case .transfer: return Palette.accent
        case .tax: return Palette.violet
        default: return Palette.ink
        }
    }
}

// MARK: - Does it add up?

/// The month's check on iPhone, above the lines: adds up, or off by how much.
private struct MonthAddsUpBanner: View {
    let month: AccountMonth
    let currency: CurrencyCode

    @Environment(\.locale) private var locale

    var body: some View {
        switch month.status {
        case .off(let difference):
            let off = AmountFormat.amount(abs(difference), currency: currency, precision: .cents, locale: locale)
            let bank = month.closing.map {
                AmountFormat.amount($0, currency: currency, precision: .cents, locale: locale)
            } ?? ""
            banner(icon: "exclamationmark.triangle.fill", color: Palette.warning,
                   "Off by \(amount: off): the bank closes at \(amount: bank). A line may be missing, or listed twice.")
        case .needsBalance:
            banner(icon: "info.circle", color: Palette.accent,
                   "Type the bank's balance on the last day to check the lines.")
        default:
            EmptyView()
        }
    }

    private func banner(icon: String, color: Color, _ sentence: AmountSentence) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            AmountSentenceText(sentence)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Metrics.tileRadius, style: .continuous))
    }
}

/// *Does it add up?*: opening, money in and out, the closing balance the
/// lines lead to, and the bank's, which can be typed here.
private struct MonthAddsUpCard: View {
    let month: AccountMonth
    let currency: CurrencyCode

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale
    @State private var bankText = ""
    @State private var errorMessage: String?
    @FocusState private var isEditing: Bool

    var body: some View {
        let totals = MonthTotals(month)
        Card("Does it add up?") {
            VStack(alignment: .leading, spacing: Metrics.s) {
                row("Opening balance", month.opening)
                row("+ Money in", totals.moneyIn)
                row("− Money out", totals.moneyOut)
                row("= Closing balance", month.stretch.expectedClosing, bold: true)
                if MonthText.isStillToCome(month.through) {
                    Text("The bank's balance goes in at the check-in, on "
                        + "\(AmountFormat.mediumDate(month.through, locale: locale)).")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryInk)
                } else {
                    HStack {
                        Text("The bank says on \(AmountFormat.shortDate(month.through, locale: locale))")
                            .foregroundStyle(Palette.secondaryInk)
                        Spacer(minLength: Metrics.s)
                        TextField("Balance", text: $bankText)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                            .focused($isEditing)
                            .onSubmit { saveBank() }
                            #if os(iOS)
                            .numberKeyboard(.numbersAndPunctuation)
                            #endif
                    }
                }
                status
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Palette.critical)
                }
            }
        }
        .onAppear { bankText = month.closing.map { AmountInput.text(for: $0, locale: locale) } ?? "" }
        .onChange(of: month.closing) { _, closing in
            if !isEditing { bankText = closing.map { AmountInput.text(for: $0, locale: locale) } ?? "" }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { saveBank() }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch month.status {
        case .off(let difference):
            let off = AmountFormat.amount(abs(difference), currency: currency, precision: .cents, locale: locale)
            Label {
                AmountSentenceText("Off by \(amount: off): a line is missing or wrong")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(Palette.warning)
        case .toCheck, .checked:
            Label("Adds up", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Palette.good)
        default:
            EmptyView()
        }
    }

    private func row(_ title: String, _ amount: Decimal?, bold: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(bold ? Palette.ink : Palette.secondaryInk)
            Spacer(minLength: Metrics.s)
            if let amount {
                AmountText(amount, currency: currency, precision: .cents)
            } else {
                Text("—")
                    .foregroundStyle(Palette.secondaryInk)
            }
        }
        .font(bold ? .body.weight(.semibold) : .body)
    }

    /// Saves the bank's balance typed, when it's a number that changed.
    private func saveBank() {
        guard case .value(let balance) = AmountInput.parse(bankText, locale: locale) else {
            errorMessage = bankText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : "Type an amount."
            return
        }
        errorMessage = nil
        guard balance != month.closing, !MonthText.isStillToCome(month.through) else { return }
        do {
            try library.update { $0.setBankBalance(balance, of: month.account, on: month.through) }
        } catch {
            errorMessage = LibraryStore.describe(error)
        }
    }
}

// MARK: - Totals

/// What the month's lines add up to.
private struct MonthTotalsCard: View {
    let month: AccountMonth
    let account: Account

    @Environment(\.locale) private var locale

    var body: some View {
        let totals = MonthTotals(month)
        Card(MonthText.title(month.through, locale: locale)) {
            VStack(alignment: .leading, spacing: Metrics.s) {
                row("Came in", totals.cameIn)
                if account.kind.recordsInterest { row("Interest", totals.interest) }
                if totals.oneOffs != 0 { row("One-offs", totals.oneOffs) }
                row("Tax", -totals.tax)
                row("Spent", -totals.spent)
                row("Moved to and from your accounts", totals.moved)
                Divider()
                row("Saved", totals.saved, bold: true)
                if let rate = rate(totals) {
                    Text("Savings rate \(AmountFormat.percent(rate, digits: 0, locale: locale))")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        }
    }

    private func rate(_ totals: MonthTotals) -> Double? {
        let income = totals.cameIn + totals.interest - totals.tax
        guard income > 0 else { return nil }
        return (totals.saved / income).doubleValue
    }

    private func row(_ title: String, _ amount: Decimal, bold: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(bold ? Palette.ink : Palette.secondaryInk)
            Spacer(minLength: Metrics.s)
            AmountText(amount, currency: account.currency, precision: .cents)
        }
        .font(bold ? .headline : .body)
    }
}

/// *The months after it*: each later month of the account, the balance it
/// opens at and whether it still adds up.
private struct MonthsAfterCard: View {
    let month: AccountMonth
    let next: CalendarDate
    let currency: CurrencyCode

    @Environment(LibraryStore.self) private var library
    @Environment(\.locale) private var locale

    var body: some View {
        let after = Array(library.library.accountMonths(of: month.account, after: month.through, next: next).prefix(3))
        if !after.isEmpty {
            Card("The months after it") {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    Text("Each month opens at the bank's balance at the end of the month before, so a change here "
                        + "shows whether the next still adds up.")
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(after) { later in
                        HStack(alignment: .firstTextBaseline) {
                            Text(MonthText.title(later.through, locale: locale))
                                .font(.body.weight(.semibold))
                                .privacySensitiveInFeedback()
                            Spacer(minLength: Metrics.s)
                            AmountSentenceText(MonthText.status(later, currency: currency, locale: locale))
                                .font(.subheadline)
                                .foregroundStyle(later.status.isDone ? Palette.good : Palette.secondaryInk)
                        }
                    }
                }
            }
        }
    }
}

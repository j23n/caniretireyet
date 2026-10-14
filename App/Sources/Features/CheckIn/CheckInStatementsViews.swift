import Model
import SwiftUI
import Tracker

/// The card a check-in opens with while it holds no statement yet (UI.md,
/// "Statements first"): what a statement fills in, the accounts it can
/// fill in with when their last value came from one, *Add Statements…* and
/// *Type Every Value Instead*.
struct CheckInStatementsStart: View {
    let statements: CheckInStatements
    let session: CheckInSession

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 40))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(verbatim: statements.startTitle(locale: locale))
                    .font(.title3.bold())
                    .privacySensitiveInFeedback()
                Text(verbatim: CheckInStatements.startMessage)
                    .foregroundStyle(Palette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(statements.accounts) { account in
                    Divider()
                    CheckInStatementAccountLine(account: account)
                        .padding(.vertical, 9)
                }
            }
            .padding(.top, Metrics.xs)
            if let error = session.statementsError {
                Text(verbatim: error)
                    .font(.footnote)
                    .foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitiveInFeedback()
            }
            Button {
                session.choosesStatements = true
            } label: {
                Text("Add Statements…")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Type Every Value Instead") {
                withAnimation { session.typesEveryValue = true }
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity)
        }
    }
}

/// An account of the start card: its name, and "last: 31 Aug" when its
/// last value was imported, else "typed by hand".
struct CheckInStatementAccountLine: View {
    let account: CheckInStatements.Account

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: Metrics.s) {
            Text(verbatim: account.name)
                .privacySensitiveInFeedback()
            Spacer(minLength: Metrics.s)
            Text(verbatim: CheckInStatements.status(of: account, locale: locale))
                .foregroundStyle(Palette.secondaryInk)
                .privacySensitiveInFeedback()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The count of a file's lines to answer, in an orange circle.
struct CheckInLinesBadge: View {
    let count: Int
    var size: CGFloat = 22

    var body: some View {
        Text(verbatim: "\(count)")
            .font(.system(size: size * 0.55, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: size, minHeight: size)
            .background(Palette.warning, in: Capsule())
            .accessibilityHidden(true)
    }
}

#if os(iOS)
/// One statement file the check-in holds, in the iPhone's Statements
/// section: with lines to answer, "② Lines to answer · Conto Fineco · 1–30
/// Sep ›", opening that file's Income; answered, "✓ Girokonto · 1–30 Sep ·
/// 48 lines · all answered"; without an account, a row that opens the
/// import's Files step to choose it. Its menu takes the file out.
struct CheckInStatementFileRow: View {
    let file: CheckInStatements.File
    let session: CheckInSession

    @Environment(CheckInStore.self) private var checkIn
    @Environment(\.locale) private var locale

    var body: some View {
        content
            .contextMenu {
                Button(role: .destructive) {
                    checkIn.removeStatement(file: file.id)
                } label: {
                    Label("Remove From Check-in", systemImage: "minus.circle")
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if file.account == nil {
            Button {
                session.showStatementFiles(checkIn: checkIn)
            } label: {
                line(title: "Choose the account", subtitle: file.name, isWarning: true) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.warning)
                }
            }
            .accessibilityHint("Opens the file to choose its account")
        } else if file.toAnswer > 0 {
            Button {
                session.answer(file: file.id, checkIn: checkIn)
            } label: {
                line(title: "Lines to answer", subtitle: CheckInStatements.subtitle(of: file, locale: locale),
                     isWarning: true) {
                    CheckInLinesBadge(count: file.toAnswer)
                }
            }
            .accessibilityLabel(Text(verbatim: Wording.count(file.toAnswer, "line") + " to answer, "
                + CheckInStatements.subtitle(of: file, locale: locale)))
            .accessibilityHint("Opens the file's income")
        } else {
            Button {
                session.answer(file: file.id, checkIn: checkIn)
            } label: {
                line(title: file.accountName ?? file.name,
                     subtitle: CheckInStatements.subtitle(of: file, locale: locale),
                     isWarning: false) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.good)
                }
            }
            .accessibilityHint("Opens the file's income")
        }
    }

    private func line(title: String, subtitle: String, isWarning: Bool,
                      @ViewBuilder icon: () -> some View) -> some View {
        HStack(spacing: Metrics.m) {
            icon()
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .fontWeight(isWarning ? .semibold : .regular)
                    .foregroundStyle(isWarning ? Palette.warning : Palette.ink)
                    .privacySensitiveInFeedback(!isWarning)
                Text(verbatim: subtitle)
                    .font(.footnote)
                    .foregroundStyle(Palette.secondaryInk)
                    .privacySensitiveInFeedback()
            }
            Spacer(minLength: Metrics.s)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.mutedInk)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
#endif

#if os(macOS)
/// The Mac's statements, above the table: the card that asks for them
/// first; then "SEPTEMBER'S STATEMENTS · 2" over a card with a line per
/// file (its account and name, its days and how its account was found,
/// its lines, and *Answer…* or "All answered") and a last line to drop
/// more on or *Add Statements…*. The whole card takes dropped files
/// (`addFiles`), ahead of the window's own drop, which starts an import.
struct CheckInStatementsBox: View {
    let statements: CheckInStatements
    let session: CheckInSession
    /// Adds files dropped on the card to the check-in.
    let addFiles: ([URL]) -> Void

    @Environment(CheckInStore.self) private var checkIn
    @Environment(\.locale) private var locale
    @State private var isTargeted = false

    var body: some View {
        Group {
            if statements.showsStart(dismissed: session.typesEveryValue) {
                CheckInStatementsStart(statements: statements, session: session)
                    .padding(Metrics.l)
                    .frame(maxWidth: 460, alignment: .leading)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(dropRing)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: statements.header(locale: locale).uppercased(with: locale))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.secondaryInk)
                        .privacySensitiveInFeedback()
                    card
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            addFiles(urls)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var card: some View {
        VStack(spacing: 0) {
            ForEach(statements.files) { file in
                fileRow(file)
                Divider()
            }
            dropRow
            if let note = statements.unreadableNote ?? session.statementsError {
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .privacySensitiveInFeedback()
            }
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        }
        .overlay(dropRing)
    }

    /// The accent ring while files are dragged over the card.
    private var dropRing: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Palette.accent, lineWidth: isTargeted ? 2 : 0)
    }

    /// The file's columns: its icon, "Conto Fineco · movimenti_settembre.csv",
    /// its days, "63 lines" and the action.
    private func fileRow(_ file: CheckInStatements.File) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 22)
                .accessibilityHidden(true)
            HStack(spacing: 4) {
                Text(verbatim: file.accountName ?? "No account")
                    .fontWeight(.semibold)
                    .layoutPriority(1)
                Text(verbatim: "· " + file.name)
                    .foregroundStyle(Palette.secondaryInk)
                    .truncationMode(.middle)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .privacySensitiveInFeedback()
            Text(verbatim: CheckInStatements.detail(of: file, locale: locale))
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .privacySensitiveInFeedback()
            Text(verbatim: CheckInStatements.lineCount(of: file))
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .monospacedDigit()
                .frame(width: 90, alignment: .trailing)
            action(file)
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contextMenu {
            Button("Show in Import…") {
                session.answer(file: file.id, checkIn: checkIn)
            }
            Button("Remove From Check-in") {
                checkIn.removeStatement(file: file.id)
            }
        }
    }

    /// *② Answer…*, "✓ All answered", or *Choose Account…* for a file
    /// without one.
    @ViewBuilder
    private func action(_ file: CheckInStatements.File) -> some View {
        if file.account == nil {
            Button("Choose Account…") {
                session.showStatementFiles(checkIn: checkIn)
            }
            .buttonStyle(.link)
        } else if file.toAnswer > 0 {
            Button {
                session.answer(file: file.id, checkIn: checkIn)
            } label: {
                HStack(spacing: 6) {
                    CheckInLinesBadge(count: file.toAnswer, size: 16)
                    Text("Answer…")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .foregroundStyle(Palette.warning)
                .background(Palette.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Palette.warning.opacity(0.45), lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "Answer " + Wording.count(file.toAnswer, "line")))
            .help("Opens the file's Income to answer its lines")
        } else {
            Label("All answered", systemImage: "checkmark.circle.fill")
                .fontWeight(.semibold)
                .foregroundStyle(Palette.good)
        }
    }

    /// "+ Drop more statements here, or Add Statements… · last time also:
    /// Conto deposito" and *Add Statements…*.
    private var dropRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .foregroundStyle(Palette.secondaryInk)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(verbatim: statements.dropHint)
                .font(.caption)
                .foregroundStyle(Palette.secondaryInk)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .privacySensitiveInFeedback()
            Button("Add Statements…") { session.choosesStatements = true }
                .buttonStyle(.link)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Palette.page)
    }
}
#endif

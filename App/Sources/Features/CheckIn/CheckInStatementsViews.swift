import Model
import SwiftUI
import Tracker

/// The card a check-in opens with while no statement is imported yet
/// (UI.md, "Statements first"): what a statement fills in, the accounts it
/// fills in, *Add Statements…* and *Type Every Value Instead*.
struct CheckInStatementsStart: View {
    let statements: CheckInStatements
    let session: CheckInSession

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            Image(systemName: "doc.text")
                .font(.system(size: 30))
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
                    CheckInStatementLine(account: account)
                        .padding(.vertical, Metrics.s)
                }
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

/// One account a statement fills in: its name, then "Imported" with a
/// check, or when its last value is from.
struct CheckInStatementLine: View {
    let account: CheckInStatements.Account

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: Metrics.s) {
            Image(systemName: account.isImported ? "checkmark.circle.fill" : "doc.text")
                .foregroundStyle(account.isImported ? Palette.positive : Palette.mutedInk)
                .accessibilityHidden(true)
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

#if os(macOS)
/// The Mac's statements, above the table: the card that asks for them
/// first, or once one is imported (or the card is put away) a box with a
/// line per account and *Add Statements…*.
struct CheckInStatementsBox: View {
    let statements: CheckInStatements
    let session: CheckInSession

    var body: some View {
        Group {
            if statements.showsStart(dismissed: session.typesEveryValue) {
                CheckInStatementsStart(statements: statements, session: session)
                    .frame(maxWidth: 460)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Statements")
                            .font(.headline)
                        if !statements.accounts.isEmpty {
                            Text(verbatim: statements.progress)
                                .foregroundStyle(Palette.secondaryInk)
                        }
                        Spacer()
                        Button("Add Statements…") { session.choosesStatements = true }
                    }
                    .padding(.bottom, Metrics.s)
                    if statements.accounts.isEmpty {
                        Text("Your bank's CSV fills in a cash or savings account's balance and what came in and "
                            + "went out.")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    ForEach(statements.accounts) { account in
                        Divider()
                        CheckInStatementLine(account: account)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
        .padding(Metrics.l)
        .background(Palette.page, in: RoundedRectangle(cornerRadius: Metrics.cardRadius / 2))
    }
}
#endif

import Foundation
import Importer
import Model
import SwiftUI

/// A line to answer as money moved to or from one of your accounts, and
/// whether the sheet starts on *A New Account* (All Lines' *A New
/// Account…*).
struct StatementMoveRequest: Identifiable, Hashable {
    var line: BatchStatementLine
    var startsWithPurchase = false

    var id: String { line.id }
}

/// *Moved to or From*: answers a line as money moved to or from one of your
/// accounts (UI.md, "Import"; IMPORT.md, "Moved to or from an account"):
/// *Your accounts*, tax pots first, each with what it is; for money in, an
/// account *Sold*; for money out, *A New Account*, a purchase you keep, with
/// its name, kind and worth. A move to one of your accounts can be every
/// line with the line's words, a rule kept for next month's statements. It
/// opens with the line's answer, when it has one.
struct ImportMovedSheet: View {
    let model: ImportController
    let line: BatchStatementLine

    /// Where the money went or came from.
    private enum Choice: Hashable {
        case account(AccountID)
        case sale(AccountID)
        case purchase
    }

    @State private var choice: Choice?
    @State private var name: String
    @State private var kind: AccountKind
    @State private var everyLine = false
    @Environment(\.dismiss) private var dismiss

    init(model: ImportController, request: StatementMoveRequest) {
        self.model = model
        line = request.line
        var choice: Choice? = request.startsWithPurchase ? .purchase : nil
        var name = ""
        var kind = AccountKind.belongings
        switch model.flow.statementAnswer(request.line) {
        case .moved(let id)?: choice = .account(id)
        case .sale(let id)?: choice = .sale(id)
        case .purchase(let purchased, let purchasedKind)?:
            choice = .purchase
            name = purchased
            kind = purchasedKind
        case nil: break
        }
        _choice = State(initialValue: choice)
        _name = State(initialValue: name)
        _kind = State(initialValue: kind)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The words a rule for every such line has.
    private var phrase: String { ImportFlow.suggestedRulePhrase(for: line.line) }
    private var currency: CurrencyCode? { model.flow.currency(of: line) }

    var body: some View {
        let flow = model.flow
        let accounts = flow.moveChoices(for: line)
        let sales = flow.saleChoices(for: line)
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: line.title.isEmpty ? "—" : line.title)
                                .fontWeight(.semibold)
                                .lineLimit(2)
                                .privacySensitiveInFeedback()
                            Spacer(minLength: Metrics.m)
                            AmountText(line.amount, currency: currency, precision: .cents, signed: true)
                        }
                        Text(verbatim: flow.dateAndAccount(line))
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                            .privacySensitiveInFeedback()
                    }
                } footer: {
                    Text(line.amount < 0
                         ? "Money moved to something you own isn't spent. Which account did it go to?"
                         : "Money moved from something you own didn't come in. Which account did it come from?")
                }

                if !accounts.isEmpty {
                    Section {
                        ForEach(accounts, id: \.id) { account in
                            choiceRow(.account(account.id)) {
                                Text(verbatim: account.name)
                                    .privacySensitiveInFeedback()
                                Spacer(minLength: Metrics.m)
                                Text(ImportFlow.moveChoiceNote(account))
                                    .font(.footnote)
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                    } header: {
                        Text("Your accounts")
                    }
                }

                if case .account? = choice, let count = flow.linesMatching(rule: phrase) {
                    Section {
                        Toggle(isOn: $everyLine) {
                            Text(verbatim: "Every line with “\(phrase)”")
                                .privacySensitiveInFeedback()
                        }
                    } footer: {
                        Text(Wording.count(count, "line") + " in these statements. The rule is kept for next "
                            + "month's statements, so their lines move too.")
                    }
                }

                if !sales.isEmpty {
                    Section {
                        ForEach(sales, id: \.id) { account in
                            choiceRow(.sale(account.id)) {
                                Text(verbatim: account.name)
                                    .privacySensitiveInFeedback()
                                Spacer(minLength: Metrics.m)
                                Text("sold")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.secondaryInk)
                            }
                        }
                    } header: {
                        Text("Sold")
                    } footer: {
                        Text(Self.footer)
                    }
                }

                if line.amount < 0 {
                    Section {
                        Button {
                            choice = .purchase
                        } label: {
                            HStack {
                                Text("A New Account")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Palette.accent)
                                Spacer(minLength: Metrics.m)
                                if choice == .purchase {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Palette.accent)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(choice == .purchase ? .isSelected : [])
                        if choice == .purchase {
                            LabeledContent("Name") {
                                TextField("Name", text: $name, prompt: Text("Car"))
                                    .multilineTextAlignment(.trailing)
                                    .labelsHidden()
                            }
                            Picker("Kind", selection: $kind) {
                                ForEach(StatementAsset.purchaseKinds, id: \.self) { kind in
                                    Text(kind.displayName).tag(kind)
                                }
                            }
                            .pickerStyle(.menu)
                            LabeledContent {
                                AmountText(-line.amount, currency: currency, precision: .cents)
                            } label: {
                                Text(verbatim: "Worth on \(AmountFormat.mediumDate(line.date))")
                                    .privacySensitiveInFeedback()
                            }
                        }
                    } footer: {
                        Text(Self.footer)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Moved to or From")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                    .disabled(choice == nil || (choice == .purchase && trimmedName.isEmpty))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 480, idealHeight: 560)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private static let footer = "A purchase you keep starts an account worth what you paid. Money in from an "
        + "account you sold closes it."

    /// A row that picks `value`, with a check while it's picked.
    private func choiceRow<Content: View>(_ value: Choice, @ViewBuilder content: () -> Content) -> some View {
        Button {
            choice = value
        } label: {
            HStack {
                content()
                if choice == value {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice == value ? .isSelected : [])
    }

    private func save() {
        switch choice {
        case .account(let id)?:
            if everyLine {
                // The line's own answer or class would take the rule's place.
                model.flow.editSession(ofFile: line.file) { session in
                    session.setStatementAsset(nil, forRow: line.row)
                    session.setStatementClass(nil, forRow: line.row)
                }
                model.flow.setStatementRule(movingTo: id, for: phrase)
            } else {
                model.flow.setStatementAsset(.moved(id), for: line)
            }
        case .sale(let id)?:
            model.flow.setStatementAsset(.sale(id), for: line)
        case .purchase?:
            model.flow.setStatementAsset(.purchase(name: trimmedName, kind: kind), for: line)
        case nil:
            break
        }
    }
}

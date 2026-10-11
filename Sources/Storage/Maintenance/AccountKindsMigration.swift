import Foundation
import Model

extension Migration {
    /// The step from version 3 to 4: each account kind records its money one
    /// way (docs/ACCOUNTS.md, "Migration"). In this order, it
    ///
    /// 1. drops `moneyInOut` from every account;
    /// 2. drops `valuation` from an account recorded as snapshots (`holdings`,
    ///    written or by default) that has no values, so it records what its
    ///    kind does now;
    /// 3. sets an account recorded as snapshots whose values all hold a
    ///    balance to `"valuation": "balance"`;
    /// 4. turns a brokerage, crypto or metals account recorded as a balance
    ///    into kind `other`, without a `valuation` key, and gives each of its
    ///    values after the first that has no `flow` the one version 3 filled
    ///    in, the whole change since the value before: as `other` its flow
    ///    would be asked for, so the change would count as market;
    /// 5. writes `"valuation": "holdings"` on the snapshot accounts left,
    ///    whose values hold positions or cash, where it was the default: the
    ///    default is trades now, and a later step converts them.
    ///
    /// Every account keeps its values and new money.
    public static let accountKinds = Migration(
        from: 3,
        summary: "Each kind of account records its money one way: money in and out on every cash and savings "
            + "account, and trades for brokerage, crypto and metals accounts. Investment accounts recorded as a "
            + "balance became other accounts.",
        apply: { files in
        var valued = Set<String>()
        var notBalance = Set<String>()
        for (path, json) in files where path.hasPrefix("history/") {
            for valuation in json["valuations"]?.arrayValue ?? [] {
                guard let account = valuation["account"]?.stringValue else { continue }
                valued.insert(account)
                if valuation["balance"].map({ $0.isNull }) ?? true { notBalance.insert(account) }
            }
        }
        var becameOther = Set<String>()
        for path in files.keys.sorted() where path.hasPrefix("accounts/") && path.hasSuffix(".json") {
            guard case .object(var account)? = files[path] else { continue }
            let id = String(path.dropFirst("accounts/".count).dropLast(".json".count))
            let original = account
            account["moneyInOut"] = nil
            let kind = AccountKind(rawValue: account["kind"]?.stringValue ?? "")
            let written = account["valuation"]?.stringValue.map(ValuationMode.init(rawValue:))
            if written ?? Migration.version3Mode(of: kind) == .holdings {
                if !valued.contains(id) {
                    account["valuation"] = nil
                } else if !notBalance.contains(id) {
                    account["valuation"] = .string(ValuationMode.balance.rawValue)
                } else {
                    account["valuation"] = .string(ValuationMode.holdings.rawValue)
                }
            }
            if kind.isInvestment, account["valuation"]?.stringValue == ValuationMode.balance.rawValue {
                account["kind"] = .string(AccountKind.other.rawValue)
                account["valuation"] = nil
                becameOther.insert(id)
            }
            if account != original { files[path] = .object(account) }
        }
        fillFlows(of: becameOther, in: &files)
    })

    /// Gives each value of `accounts` after its first that records a
    /// balance and no `flow` the whole change since the value before as its
    /// flow, as version 3 filled it in for a brokerage, crypto or metals
    /// account's balance.
    private static func fillFlows(of accounts: Set<String>, in files: inout [String: JSONValue]) {
        guard !accounts.isEmpty else { return }
        typealias Entry = (date: String, path: String, index: Int, balance: Decimal?, hasFlow: Bool)
        var entries: [String: [Entry]] = [:]
        for (path, json) in files where path.hasPrefix("history/") {
            for (index, valuation) in (json["valuations"]?.arrayValue ?? []).enumerated() {
                guard let account = valuation["account"]?.stringValue, accounts.contains(account),
                      let date = valuation["date"]?.stringValue
                else { continue }
                entries[account, default: []].append(
                    (date, path, index, valuation["balance"]?.decimalValue,
                     !(valuation["flow"].map(\.isNull) ?? true)))
            }
        }
        for list in entries.values {
            let sorted = list.sorted { ($0.date, $0.path, $0.index) < ($1.date, $1.path, $1.index) }
            for (previous, entry) in zip(sorted, sorted.dropFirst()) where !entry.hasFlow {
                guard let before = previous.balance, let now = entry.balance,
                      var valuations = files[entry.path]?["valuations"]?.arrayValue
                else { continue }
                let flow = JSONValue.string((now - before).rounded(scale: 2).fileString)
                valuations[entry.index] = valuations[entry.index].withMember("flow", to: flow)
                files[entry.path] = files[entry.path]?.withMember("valuations", to: .array(valuations))
            }
        }
    }

    /// An account's valuation mode by default in format version 3.
    static func version3Mode(of kind: AccountKind) -> ValuationMode {
        kind.isInvestment ? .holdings : .balance
    }
}

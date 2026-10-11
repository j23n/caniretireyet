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
    ///    into kind `other`, without a `valuation` key;
    /// 5. writes `"valuation": "holdings"` on the snapshot accounts left,
    ///    whose values hold positions or cash, where it was the default: the
    ///    default is trades now, and a later step converts them.
    ///
    /// Values aren't changed, so every account keeps its values and new money.
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
            }
            if account != original { files[path] = .object(account) }
        }
    })

    /// An account's valuation mode by default in format version 3.
    static func version3Mode(of kind: AccountKind) -> ValuationMode {
        kind.isInvestment ? .holdings : .balance
    }
}

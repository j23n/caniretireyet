import Foundation
import Model

extension Migration {
    /// The step from version 4 to 5 (docs/schema/README.md, "Versioning").
    /// It
    ///
    /// 1. renames account kind `vehicle` to `belongings`, and the statement
    ///    class `paidBack` to `spending` in import profiles' rules and
    ///    answers;
    /// 2. writes a plan's return given by both `real` and `medianReal` with
    ///    `medianReal` alone, in plans and in the copies of plans that baselines keep;
    /// 3. drops a valuation's `flow` where its account doesn't ask for one
    ///    (``Model/Account/asksForFlow``): that flow is worked out from the
    ///    account's records, so a missing one means "computed". A savings
    ///    value without `interest` whose flow wasn't its change gets the
    ///    difference as its interest, so what it saved stays; a note names
    ///    each other balance whose flows weren't its change;
    /// 4. prices instruments priced from CoinGecko from Yahoo Finance, as
    ///    the coin's pair in the instrument's currency (`BTC-EUR`), when the
    ///    instrument says the coin's ticker; otherwise their `priceSource`
    ///    goes, and a note says so.
    public static let format5 = Migration(notedApply: { files in
        renameKinds(in: &files)
        dropBothReturns(in: &files)
        let flowNotes = dropComputedFlows(in: &files)
        return flowNotes + priceCryptoFromYahoo(in: &files)
    }, from: 4, summary: "What you saved is stored only on accounts that ask for it: other values work it out from what's "
        + "recorded. Crypto is priced from Yahoo Finance, not CoinGecko.")

    // MARK: - Renamed values

    private static func renameKinds(in files: inout [String: JSONValue]) {
        for (path, json) in files {
            switch LibraryFile(path: path) {
            case .account?:
                if json["kind"]?.stringValue == "vehicle" {
                    files[path] = json.withMember("kind", to: .string(AccountKind.belongings.rawValue))
                }
            case .importProfile?:
                var profile = json
                for list in ["rules", "answers"] {
                    guard let items = json[list]?.arrayValue else { continue }
                    let renamed = items.map { item in
                        item["class"]?.stringValue == "paidBack"
                            ? item.withMember("class", to: .string(StatementClass.spending.rawValue)) : item
                    }
                    if renamed != items { profile = profile.withMember(list, to: .array(renamed)) }
                }
                if profile != json { files[path] = profile }
            default:
                break
            }
        }
    }

    // MARK: - Returns

    private static func dropBothReturns(in files: inout [String: JSONValue]) {
        for (path, json) in files {
            switch LibraryFile(path: path) {
            case .plan?:
                files[path] = withMedianReturns(json)
            case .baseline?:
                if let plan = json["plan"] { files[path] = json.withMember("plan", to: withMedianReturns(plan)) }
            default:
                break
            }
        }
    }

    /// `plan` with each return in `assumptions.returns` that gives both
    /// `real` and `medianReal` keeping only `medianReal`.
    private static func withMedianReturns(_ plan: JSONValue) -> JSONValue {
        guard let assumptions = plan["assumptions"], case .object(var returns)? = assumptions["returns"] else {
            return plan
        }
        for (assetClass, value) in returns {
            guard case .object(var members) = value, members["real"] != nil, members["medianReal"] != nil else {
                continue
            }
            members["real"] = nil
            returns[assetClass] = .object(members)
        }
        return plan.withMember("assumptions", to: assumptions.withMember("returns", to: .object(returns)))
    }

    // MARK: - Flows

    /// Drops the `flow` of every valuation whose account doesn't ask for one.
    /// A savings value without `interest` whose flow wasn't its change (one
    /// typed before values recorded interest) gets the difference as its
    /// `interest`, so what it saved stays the same. Returns a note for
    /// each other balance whose values' flows differed from what's now
    /// worked out from its balances.
    private static func dropComputedFlows(in files: inout [String: JSONValue]) -> [String] {
        var computed: [String: Account] = [:]
        for (path, json) in files {
            guard case .account(let id)? = LibraryFile(path: path),
                  let account = try? LenientDecoding.decode(Account.self,
                                                             from: json.withMember("id", to: .string(id.rawValue))),
                  !account.asksForFlow
            else { continue }
            computed[id.rawValue] = account
        }

        typealias Entry = (date: String, path: String, index: Int, valuation: JSONValue)
        var entries: [String: [Entry]] = [:]
        for (path, json) in files {
            guard case .month? = LibraryFile(path: path) else { continue }
            for (index, valuation) in (json["valuations"]?.arrayValue ?? []).enumerated() {
                guard let account = valuation["account"]?.stringValue, computed[account] != nil,
                      let date = valuation["date"]?.stringValue
                else { continue }
                entries[account, default: []].append((date, path, index, valuation))
            }
        }

        var notes: [String] = []
        for id in entries.keys.sorted() {
            guard let account = computed[id], let list = entries[id] else { continue }
            let sorted = list.sorted { ($0.date, $0.path, $0.index) < ($1.date, $1.path, $1.index) }
            var differed = 0
            var previousBalance: Decimal?
            for entry in sorted {
                defer { previousBalance = entry.valuation["balance"]?.decimalValue }
                guard case .object(var members) = entry.valuation, let flow = members["flow"]?.decimalValue else {
                    if entry.valuation["flow"] != nil { drop(entry, in: &files) }
                    continue
                }
                if !account.recordsTrades, let before = previousBalance, let now = members["balance"]?.decimalValue {
                    let change = now - before
                    if account.kind.defaultFlow == .changeLessInterest {
                        let interest = members["interest"]?.decimalValue
                        if interest == nil, change != flow {
                            members["interest"] = .string((change - flow).fileString)
                        } else if change - (interest ?? 0) != flow {
                            differed += 1
                        }
                    } else if change != flow {
                        differed += 1
                    }
                }
                members["flow"] = nil
                replace(entry, with: .object(members), in: &files)
            }
            if differed > 0 {
                notes.append("\(account.name): what \(Wording.count(differed, "value")) saved wasn't the change in "
                    + "balance; it's now worked out from the balances.")
            }
        }
        return notes
    }

    private static func drop(_ entry: (date: String, path: String, index: Int, valuation: JSONValue),
                             in files: inout [String: JSONValue]) {
        guard case .object(var members) = entry.valuation else { return }
        members["flow"] = nil
        replace(entry, with: .object(members), in: &files)
    }

    private static func replace(_ entry: (date: String, path: String, index: Int, valuation: JSONValue),
                                with valuation: JSONValue, in files: inout [String: JSONValue]) {
        guard let file = files[entry.path], var valuations = file["valuations"]?.arrayValue,
              valuations.indices.contains(entry.index)
        else { return }
        valuations[entry.index] = valuation
        files[entry.path] = file.withMember("valuations", to: .array(valuations))
    }

    // MARK: - Crypto prices

    /// Moves instruments priced from CoinGecko to Yahoo Finance; returns a
    /// note for each one whose Yahoo symbol can't be told.
    private static func priceCryptoFromYahoo(in files: inout [String: JSONValue]) -> [String] {
        var notes: [String] = []
        for path in files.keys.sorted() {
            guard let json = files[path], case .instrument? = LibraryFile(path: path),
                  let source = json["priceSource"], source["provider"]?.stringValue == "coingecko"
            else { continue }
            if let symbol = yahooSymbol(for: json, coinGeckoSymbol: source["symbol"]?.stringValue) {
                files[path] = json.withMember("priceSource", to: .object([
                    "provider": .string(PriceProvider.yahoo.rawValue), "symbol": .string(symbol),
                ]))
            } else {
                guard case .object(var members) = json else { continue }
                members["priceSource"] = nil
                files[path] = .object(members)
                let name = json["name"]?.stringValue ?? path
                notes.append("\(name) was priced from CoinGecko, which this app no longer uses. Add its Yahoo "
                    + "Finance symbol, such as BTC-EUR, or import its prices.")
            }
        }
        return notes
    }

    /// The coin's Yahoo Finance pair, `<TICKER>-<CURRENCY>`: the ticker is
    /// the instrument's unit (crypto is priced per coin, `BTC`), else its
    /// `ticker`, else the CoinGecko symbol when it's written as a ticker
    /// (`ETH`; a lowercase one can be a CoinGecko ID, `bitcoin`). `nil`
    /// when none says it, or without a currency.
    static func yahooSymbol(for instrument: JSONValue, coinGeckoSymbol: String?) -> String? {
        guard let currency = instrument["currency"]?.stringValue, isTicker(currency) else { return nil }
        let units: Set<InstrumentUnit> = [.share, .gram, .kilogram, .troyOunce]
        let unit = instrument["unit"]?.stringValue.flatMap { units.contains(InstrumentUnit($0)) ? nil : $0 }
        let ticker = [unit, instrument["ticker"]?.stringValue].compactMap { $0 }.first(where: isTicker)
            ?? coinGeckoSymbol.flatMap { isTicker($0) && $0 == $0.uppercased() ? $0 : nil }
        return ticker.map { "\($0.uppercased())-\(currency.uppercased())" }
    }

    /// Letters and digits only, 2 to 10 of them.
    private static func isTicker(_ text: String) -> Bool {
        (2...10).contains(text.count) && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

import Foundation
import Model

extension Migration {
    /// 2 → 3: plans without tax systems (PLANNER.md). Income from work and
    /// pensions is entered after tax, plans set two tax rates by hand, and
    /// accounts say from what age plans can draw on them.
    ///
    /// What can be carried over is:
    ///
    /// - **Plans.** The residence in force this year becomes the rates: the
    ///   generic system's `capitalGainsRate` and `wealthTaxRate` as written;
    ///   Italy 26% on investments and the 0.2% stamp duty on them as a wealth
    ///   tax; Germany 26.375% (25% and the solidarity surcharge). Swiss rates
    ///   depend on the canton and aren't guessed. Net work phases and `fixed`
    ///   pensions stay. A phase stated gross and a pension projected by a
    ///   scheme keep their dates, and their name says what they were, for
    ///   the amount after tax to be entered. Contributions into a pension
    ///   scheme, event kinds, `withdrawals` and the plan's `currency` go; a
    ///   plan in another currency than the library's says so in its name.
    /// - **Accounts.** The tax wrapper goes; a pension wrapper sets
    ///   `availableFromAge` to the age it paid out from in the old rules
    ///   (``availableFromAge(wrapper:)``).
    /// - **Instruments** lose their tax overrides, and the person their
    ///   citizenships.
    public static let simplePlans = Migration(
        from: 2,
        summary: "Plans take income and pensions after tax and two tax rates; accounts get availableFromAge"
    ) { documents in
        let base = documents[LibraryFile.settings.path]?["baseCurrency"]?.stringValue
        let year = CalendarDate.today().year
        for path in documents.keys.sorted() {
            guard case .object(var object) = documents[path] else { continue }
            if path == LibraryFile.settings.path {
                if case .object(var person) = object["person"] {
                    person["citizenships"] = nil
                    object["person"] = .object(person)
                }
            } else if path.hasPrefix("accounts/") {
                if let wrapper = object["tax"]?["wrapper"]?.stringValue, object["availableFromAge"] == nil,
                   let age = availableFromAge(wrapper: wrapper) {
                    object["availableFromAge"] = .number(Decimal(age))
                }
                object["tax"] = nil
            } else if path.hasPrefix("instruments/") {
                object["tax"] = nil
            } else if path.hasPrefix("plans/") {
                simplifyPlan(&object, baseCurrency: base, year: year)
            }
            documents[path] = .object(object)
        }
    }

    /// The age a pension wrapper of the old tax systems paid out from: the
    /// age plans can draw on such an account. `nil` for wrappers that could
    /// be drawn at any age (ordinary accounts, Italy's TFR, paid when a job ends).
    static func availableFromAge(wrapper: String) -> Int? {
        switch wrapper {
        case "it.pensionFund": 67
        case "ch.pillar3a", "ch.vestedBenefits": 60
        case "ch.bvg": 65
        case "de.riester", "de.ruerup", "de.bav": 62
        default: nil
        }
    }

    /// The tax rates a residence of the old tax systems comes to:
    /// `investmentRate` and `wealthRate`, as file strings.
    static func rates(system: String, options: [String: JSONValue]) -> (investment: JSONValue?, wealth: JSONValue?) {
        switch system {
        case "generic":
            (options["capitalGainsRate"] ?? options["interestDividendRate"], options["wealthTaxRate"])
        case "it":
            ("0.26", "0.002")
        case "de":
            ("0.26375", nil)
        default:
            (nil, nil)
        }
    }

    private static func simplifyPlan(_ plan: inout [String: JSONValue], baseCurrency: String?, year: Int) {
        // Taxes: the residence in force this year (else the first) becomes the
        // rates, unless the plan already has them.
        var tax = plan["tax"]?.objectValue ?? [:]
        let residence = (tax["residence"]?.arrayValue ?? []).compactMap(\.objectValue)
        for key in ["residence", "overlays", "overrides", "indexThresholds"] { tax[key] = nil }
        let current = residence.filter { ($0["from"]?.intValue ?? .min) <= year }
            .max { ($0["from"]?.intValue ?? .min) < ($1["from"]?.intValue ?? .min) } ?? residence.first
        if let current, let system = current["system"]?.stringValue {
            let (investment, wealth) = rates(system: system, options: current["options"]?.objectValue ?? [:])
            tax["investmentRate"] = tax["investmentRate"] ?? investment
            tax["wealthRate"] = tax["wealthRate"] ?? wealth
        }
        plan["tax"] = tax.isEmpty ? nil : .object(tax)

        // Work: net phases stay; a gross one keeps its dates and says what it was.
        if let work = plan["work"]?.arrayValue {
            plan["work"] = .array(work.map { entry in
                guard var phase = entry.objectValue else { return entry }
                if phase["netIncome"] == nil, phase["name"] == nil {
                    phase["name"] = .string(previousWork(phase))
                }
                for key in ["kind", "grossSalary", "revenue", "costs", "regime", "options"] { phase[key] = nil }
                return .object(phase)
            })
        }

        // Pensions: an amount from an age stays; a scheme's keeps a name and its claim age.
        if let pensions = plan["pensions"]?.arrayValue {
            plan["pensions"] = .array(pensions.map { entry in
                guard let pension = entry.objectValue else { return entry }
                var simple: [String: JSONValue] = [:]
                let scheme = pension["scheme"]?.stringValue ?? "fixed"
                if scheme == "fixed" {
                    simple["name"] = pension["name"]
                    simple["fromAge"] = pension["fromAge"]
                    simple["perYear"] = pension["perYear"]
                } else {
                    simple["name"] = .string(pension["name"]?.stringValue ?? "Pension (\(scheme))")
                    simple["fromAge"] = pension["claim"]?.intValue.map { .number(Decimal($0)) }
                }
                return .object(simple)
            })
        }

        // Contributions into a pension scheme go; into an account they stay.
        if let contributions = plan["contributions"]?.arrayValue {
            let kept = contributions.compactMap { entry -> JSONValue? in
                guard var contribution = entry.objectValue else { return entry }
                guard contribution["pension"] == nil else { return nil }
                contribution["pension"] = nil
                return .object(contribution)
            }
            plan["contributions"] = kept.isEmpty ? nil : .array(kept)
        }

        if let events = plan["events"]?.arrayValue {
            plan["events"] = .array(events.map { entry in
                guard var event = entry.objectValue else { return entry }
                event["kind"] = nil
                return .object(event)
            })
        }
        plan["withdrawals"] = nil
        if let currency = plan["currency"]?.stringValue {
            if currency != baseCurrency, let name = plan["name"]?.stringValue {
                plan["name"] = .string("\(name) (amounts in \(currency))")
            }
            plan["currency"] = nil
        }
    }

    /// A gross work phase as a name, e.g. "Employee, gross 65000 a year".
    private static func previousWork(_ phase: [String: JSONValue]) -> String {
        func amount(_ key: String) -> String? { phase[key]?.decimalValue.map { $0.fileString } }
        switch phase["kind"]?.stringValue {
        case "employee":
            return amount("grossSalary").map { "Employee, gross \($0) a year" } ?? "Employee"
        case "selfEmployed":
            let revenue = amount("revenue").map { "revenue \($0)" }
            let costs = amount("costs").map { "costs \($0)" }
            let parts = [revenue, costs].compactMap { $0 }
            return parts.isEmpty ? "Self-employed" : "Self-employed, " + parts.joined(separator: ", ") + " a year"
        default:
            return "Work"
        }
    }
}

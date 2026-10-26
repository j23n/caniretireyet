import Foundation
import Model
import Tracker

/// An account the plan includes but can draw from only from a later age,
/// such as a pension fund (`Account.availableFromAge`). A chapter's sheet
/// lists it in the chapter it opens in (UI.md, "Your life ahead").
public struct PlanLaterAccount: Hashable, Sendable, Identifiable {
    public var id: AccountID
    public var name: String
    /// The age from which the plan can draw from it.
    public var age: Int
    /// Its value on the day the plan starts, in the base currency; `nil`
    /// without a value then.
    public var value: Decimal?

    public init(id: AccountID, name: String, age: Int, value: Decimal?) {
        self.id = id
        self.name = name
        self.age = age
        self.value = value
    }

    /// The accounts `plan` includes that open after your age on the day it
    /// starts, as the plan counts them (PLANNER.md, "The portfolio"): open
    /// then, not a debt, not left out of the plan. By age, then name.
    public static func accounts(of plan: PlanDocument, library: Library, valuator: Valuator,
                                today: CalendarDate) -> [PlanLaterAccount] {
        guard let birthDate = library.settings.person?.birthDate else { return [] }
        let start = plan.startDate(in: library, today: today)
        let currentAge = birthDate.wholeYears(to: start)
        let excluded = Set(plan.portfolio.exclude)
        return library.accounts.values
            .filter { $0.includedInPlan && !excluded.contains($0.id) && $0.isOpen(on: start) && !$0.kind.isLiability }
            .compactMap { account -> PlanLaterAccount? in
                guard let age = account.availableFromAge, age > currentAge else { return nil }
                let value = valuator.value(of: account.id, on: start)
                    .flatMap { $0.status == .noValuation ? nil : $0.knownValue }
                return PlanLaterAccount(id: account.id, name: account.name, age: age, value: value)
            }
            .sorted { ($0.age, $0.name) < ($1.age, $1.name) }
    }
}

extension PlanChaptersModel {
    /// Of `accounts`, the ones that open in the chapter at `index`: the
    /// first chapter whose ages hold the age they open at.
    public func laterAccounts(_ accounts: [PlanLaterAccount], inChapterAt index: Int) -> [PlanLaterAccount] {
        let all = chapters.chapters
        guard all.indices.contains(index) else { return [] }
        return accounts.filter { account in
            all.firstIndex { $0.ages.contains(account.age) } == index
        }
    }
}

import Model

/// What the planner reads into a plan where the file leaves it open: the
/// day it starts from, and the names of items without one. The app and the
/// CLI show them as a run reads them.
extension PlanDocument {
    /// The day the plan starts from (PLANNER.md, "The portfolio"): its own
    /// start date, else the library's latest check-in, else `today`.
    public func startDate(in library: Library, today: CalendarDate? = nil) -> CalendarDate {
        switch portfolio.effectiveStart {
        case .date(let date): date
        case .latestCheckIn: library.latestCheckInDate ?? today ?? .today()
        }
    }

    /// The name of the work phase at `index`: its own, else "Work", or "Work 2"
    /// when there are several.
    public func workName(_ index: Int) -> String {
        work[index].name ?? (work.count == 1 ? "Work" : "Work \(index + 1)")
    }

    /// The name of the pension at `index`: its own, else "Pension", or "Pension 2"
    /// when there are several.
    public func pensionName(_ index: Int) -> String {
        pensions[index].name ?? (pensions.count == 1 ? "Pension" : "Pension \(index + 1)")
    }

    /// The name of the other income at `index`: its own, else "Other income", or
    /// "Other income 2" when there are several.
    public func incomeName(_ index: Int) -> String {
        income[index].name ?? (income.count == 1 ? "Other income" : "Other income \(index + 1)")
    }
}

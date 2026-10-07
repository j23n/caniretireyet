import Model

extension Baseline {
    /// The accounts your money is measured in against this baseline
    /// (PROGRESS.md, "Actual vs. a baseline"): those it counted at its start;
    /// those that replaced them (``Account/successor``, as when you switched
    /// banks), and theirs; and those opened since that plans count and its
    /// plan doesn't leave out, which hold new money or money moved from the
    /// others. So moving money to another account, or saving into a new one,
    /// is no loss. Accounts open at its start that it didn't count stay out.
    public func comparedAccounts(among accounts: [AccountID: Account]) -> Set<AccountID> {
        var compared = Set(self.accounts)
        let excluded = Set((try? planDocument())?.portfolio.exclude ?? [])
        for account in accounts.values
        where account.opened >= start.date && account.includedInPlan && !excluded.contains(account.id) {
            compared.insert(account.id)
        }
        var queue = Array(compared)
        while let id = queue.popLast() {
            guard let successor = accounts[id]?.successor, !compared.contains(successor) else { continue }
            compared.insert(successor)
            queue.append(successor)
        }
        return compared
    }
}

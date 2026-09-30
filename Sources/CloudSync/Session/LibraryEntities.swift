import Model
import Storage

extension Library {
    /// Replaces what each of `files` holds with `source`'s version, removing
    /// it where `source` has none. Everything else is kept.
    ///
    /// Used after reloading changed files into a copy of the library: only
    /// those files' entities are taken over, so edits made meanwhile to
    /// other files survive.
    public mutating func replaceEntities(of files: some Sequence<LibraryFile>, from source: Library) {
        for file in files {
            switch file {
            case .settings:
                settings = source.settings
            case .account(let id):
                accounts[id] = source.accounts[id]
            case .instrument(let id):
                instruments[id] = source.instruments[id]
            case .month(let month):
                months[month] = source.months[month]
            case .plan(let id):
                plans[id] = source.plans[id]
            case .importProfile(let id):
                importProfiles[id] = source.importProfiles[id]
            case .baseline(let plan, let id):
                var projections = self.projections[plan] ?? PlanProjections()
                projections.baselines[id] = source.projections[plan]?.baselines[id]
                self.projections[plan] = projections.isEmpty ? nil : projections
            case .headlines(let plan, let year):
                var projections = self.projections[plan] ?? PlanProjections()
                projections.headlines[year] = source.projections[plan]?.headlines[year]
                self.projections[plan] = projections.isEmpty ? nil : projections
            }
        }
    }
}

extension PlanProjections {
    /// Whether there are no baselines and no headline files.
    var isEmpty: Bool { baselines.isEmpty && headlines.isEmpty }
}

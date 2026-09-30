/// # Planner
///
/// The simulation engine and return model (PLANNER.md). It contains no tax
/// rules: every tax, contribution and pension rule comes from a
/// `TaxKit.TaxSystem` chosen by the plan.
///
/// - Builds the starting portfolio from the latest check-in
///   (`Tracker.Valuator`), grouped into buckets by tax wrapper.
/// - Runs yearly steps in today's euros: income, taxes (prepare once per
///   year, assess per path, gross-up for withdrawals), spending, returns.
/// - Deterministic and seeded Monte Carlo runs, the earliest-retirement-age
///   search, and the results behind the headline, charts and baselines.
///
/// Works in `Double`. Never imports a specific country's module.
///
/// Placeholder: this module is owned by another engineer.
enum PlannerModule {}

// # Glance
//
// What the widgets show (UI.md, "Widgets"), as plain values the app writes
// and the widget extension reads. The extension never opens the library: the
// app keeps a small snapshot in the App Group container, and widgets draw it.
//
// - `GlanceSnapshot` holds net worth on the latest check-in with its change
//   and a year of month ends, the asset mix, the main plan's answer with the
//   answers recorded at the year's check-ins, and when the next check-in is
//   due. `GlanceSnapshot(library:valuator:asOf:answer:checkIn:)` builds it.
// - `GlanceFile` reads and writes it as JSON; a reader skips a snapshot of a
//   newer format, so an older widget shows its placeholder instead of garbage.
// - What depends on the day a widget is drawn is worked out then, from the
//   snapshot's dates: `RetirementCountdown` ("15 y 6 m") and
//   `CheckInGlance.daysUntilDue(on:)`.
// - `GlanceLink` is where tapping a widget goes: the Overview, the Plan or
//   the check-in.
// - `GlanceText` has the words that don't involve amounts ("9 of 10",
//   "55 → 54 in June"); amounts are formatted where they're shown.
//
// Glance uses Foundation only and builds on Linux.

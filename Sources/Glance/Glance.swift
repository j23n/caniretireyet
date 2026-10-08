// # Glance
//
// What the widgets show (UI.md, "Widgets"), as plain values the app writes
// and the widget extension reads. The extension never opens the library: the
// app keeps a small snapshot in the App Group container, and widgets draw it.
//
// - `GlanceSnapshot` holds net worth today with the change at the latest
//   check-in and a year of month ends, the asset mix, the main plan's answer
//   with the answers recorded at the year's check-ins, and when the next
//   check-in is due. `GlanceSnapshot(library:valuator:asOf:answer:checkIn:)`
//   builds it; the Overview's hero is `NetWorthGlance(valuator:asOf:)`.
// - `GlanceFile` reads and writes it as JSON. The app and its widgets are
//   updated together, so the file has no format version: a field added
//   later is optional, and a snapshot that can't be read (one an earlier
//   version wrote in another shape) leaves the widgets saying to open the
//   app, until the app writes the next one, as it does when it opens.
// - What depends on the day a widget is drawn is worked out then, from the
//   snapshot's dates: `RetirementCountdown` ("15 y 6 m") and
//   `CheckInGlance.daysUntilDue(on:)`.
// - `GlanceLink` is where tapping a widget goes: the Overview, the Plan or
//   the check-in.
// - `GlanceText` has the words that don't involve amounts ("9 of 10",
//   "55 → 54 in June"); amounts are formatted where they're shown.
//
// Glance uses Foundation only and builds on Linux.

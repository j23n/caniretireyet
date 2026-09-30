# The app

The SwiftUI app for iPhone, iPad and Mac (iOS 26 / macOS 26), on top of the Swift package in the repository root. Read [docs/UI.md](../docs/UI.md) for what it looks like, and this file for how it's built and where your code goes.

Build it on a Mac: `brew install xcodegen && xcodegen generate --spec App/project.yml`, then open `App/CanIRetireYet.xcodeproj`. The project is generated from [project.yml](project.yml) and never committed.

## At a glance

```
CanIRetireYetApp (@main)          one AppModel, injected into every scene
 └─ RootView                      launch · onboarding · main navigation
     ├─ TabRoot (compact)         Overview · Accounts · Plan tabs, check-in in the tab bar accessory
     └─ SidebarRoot (regular, Mac) Overview · Check-in · Accounts… · Plans… · Library…
         └─ Features/<Feature>/<Name>Screen      ← your code
               reads and edits through the stores in the environment
Stores (@Observable, @MainActor)
 LibraryStore ─ LibrarySync (CloudSync actor) ─ LibraryFolder (Storage) ─ files
 PriceStore   ─ PriceService (Prices)
 CheckInStore ─ CheckInDraft (Tracker), kept in Application Support
 PlanStore    ─ PlanEngine (PlannerPlanEngine: the Planner and the tax registry)
 PrivacySettings · AppPreferences · AppNavigation
```

## Folders

| Folder | What goes there | Owner |
| --- | --- | --- |
| `App/` | `@main`, `AppModel` (creates the stores), environment injection, menu commands | app core |
| `Stores/` | The stores, and the logic they need that isn't UI | app core (PlanStore: Plan engineer fills in the engine) |
| `Navigation/` | Root view, tabs, sidebar, the check-in accessory, sheets, `AppNavigation` | app core |
| `DesignSystem/` | Colours, spacing, number formatting, `AmountText`, `DeltaText`, `Card`, `SectionHeader`, `StatusBanner`, input parsing, SF Symbol names | app core |
| `Components/Charts/` | Reusable Swift Charts views and their plain-value inputs | app core |
| `Features/<Feature>/` | One folder per feature, starting with its screen | feature engineers |
| `Preview/` | The made-up library, a made-up plan engine, preview helpers | app core |
| `Resources/Assets.xcassets` (next to `Sources/`) | Colour sets, light and dark | app core |

**Rules so we don't collide:** feature code lives in its `Features/` folder. Replace the body of your placeholder screen, keep its **name and initializer** (the navigation creates it), and add files next to it. If you need something in a store, the design system or the charts, prefer an extension in your feature folder; if it must change a shared file, keep the change small and additive.

Keep logic that doesn't need SwiftUI in files that import only Foundation and the package modules (like everything in `Stores/`): it can then be type-checked and tested on Linux (see [Checking without Xcode](#checking-without-xcode)).

## Screens and their contracts

| Screen | Created as | Shown by |
| --- | --- | --- |
| `OverviewScreen` | `OverviewScreen()` | Overview tab, sidebar *Overview* (with the eye and gear toolbar added by the navigation) |
| `AccountsScreen` | `AccountsScreen(filter: .all / .group(g) / .closed)` | Accounts tab, sidebar groups and *Closed* |
| `AccountDetailScreen` | `AccountDetailScreen(accountID:)` | pushing an `AccountID` on any stack (`NavigationLink(value: id)`, `navigation.showAccount(id)`) |
| `NewAccountScreen` | `NewAccountScreen()` | ⌘N, Accounts toolbar, onboarding (sheet in a NavigationStack) |
| `InstrumentsScreen` | `InstrumentsScreen()` | sidebar *Instruments*; an account's positions on iPhone. *Update Prices* and *Set Price…* live here (`InstrumentPriceUpdater`, `InstrumentPriceForm`) |
| `CheckInScreen` | `CheckInScreen()` | iPhone: full-screen cover (in a NavigationStack); Mac/iPad: sidebar *Check-in*. Close with `navigation.finishCheckIn()` |
| `PlanScreen` | `PlanScreen(planID:)`, `nil` = main plan | Plan tab, sidebar plans, pushing a `PlanID` |
| `PlanCompareScreen` | `PlanCompareScreen(firstID:)` | Plan menu *Compare Plans* (⌘⌥C), pushed on the plan's stack |
| `ImportScreen` | `ImportScreen(file:)` | ⌘⇧I, sidebar *Import…*, dropping a CSV on the window, opening a CSV from Files (sheet on iPhone) |
| `ImportProfilesScreen` | `ImportProfilesScreen()` | *Saved profiles* in the import's first step |
| `SettingsScreen` | `SettingsScreen()` inside a NavigationStack | Mac: Settings window (⌘,); iPhone/iPad: gear → sheet |
| `OnboardingScreen` | `OnboardingScreen()` | first launch, when there's no library |
| `WelcomeNextStepsView` | sheet `.welcome` | after onboarding: import or add accounts |
| `SyncScreen` | `SyncScreen()` | sidebar *Sync & backups*, Settings |

Each feature folder keeps its logic in files that import only Foundation and the package (`OverviewData`, `AccountDetailData`, `InstrumentPriceUpdate`, `CheckInModel`, `ImportFlow*`, `PlanSession`, `PlanProgressData`, …) and its views in the rest.

## Stores

All stores are `@Observable @MainActor` classes created once in `AppModel` and injected with `.appEnvironment(model)`. In a view:

```swift
@Environment(LibraryStore.self) private var library
@Environment(CheckInStore.self) private var checkIn
@Environment(PlanStore.self) private var plans
@Environment(PriceStore.self) private var prices
@Environment(AppNavigation.self) private var navigation
@Environment(PrivacySettings.self) private var privacy
@Environment(AppPreferences.self) private var preferences
```

For a binding, `@Bindable var navigation = navigation` inside `body`.

### LibraryStore — the library in memory, and keeping it in step with the folder

- **State:** `phase` (`.starting`, `.needsSetup`, `.ready`, `.failed(message)`), `library: Library` (the whole library, from Model), `revision` (goes up with every change), `location` (iCloud Drive or this device), `activity` (idle, loading, saving, syncing, moving), `lastSavedAt`, `lastSyncedAt`, `lastError`, `loadIssues` (problems in hand-edited files), `mergedConflicts` / `conflictFailures`, `saveNotices` (files a save copied to backups before replacing them, or kept, because they changed elsewhere or couldn't be read), `isReadOnly` (a newer app wrote the library), `isICloudAvailable`, `isRelocating` (being opened or moved), `canEdit`.
- **Derived:** `valuator` (a `Tracker.Valuator`, rebuilt only when the library changes), `asOfDate` (latest check-in, or today), `netWorth`, `planAssets`, `changeSinceLastCheckIn`, `staleAccounts(threshold:)`, `account(_:)`, `openAccounts`, `openAccounts(in:)`, `closedAccounts`, `accountGroups`, `sortedPlans`, `mainPlan`, `baseCurrency`, `settings`, `newAccountID(for:)`, `newPlanID(for:)`, `newInstrumentID(for:)` (these skip the IDs of files that failed to load, `unloadedFiles`).
- **Editing:** everything goes through `update(_:)`, which changes a copy, replaces `library` at once and writes only the files that changed in the background, one save at a time. `commit(_:)` does the same and waits for the write, throwing `.saveFailed` if it didn't land. They throw `LibraryStoreError.readOnly` / `.notLoaded`, and `.busy` while the library is being opened or moved; a failed write shows in `lastError` and reloads what's on disk. Each write is merged with the file on disk (FILE_FORMAT.md, "Saving"): a change that arrived from elsewhere and wasn't reloaded yet is kept (history record by record) or copied to `backups/` before it's replaced, and listed in `saveNotices`.

  ```swift
  try library.update { $0.accounts[id]?.name = newName }
  try library.upsert(valuation)
  try library.closeAccount(id, on: date, successor: other)
  ```

  Helpers (`LibraryStore+Editing.swift`): `save(_ account:)`, `closeAccount`, `reopenAccount`, `deleteAccount` (with its valuations, and clears references to it: successors, plans' excluded accounts and contributions, import profiles' matches and columns), `save(_ instrument:)`, `save(_ instrument:prices:fxRates:)` (a new instrument with its first price), `deleteInstrument`, `upsert(_ valuation:)`, `replace(_:with:)`, `removeValuation`, `saveValue(_:replacing:) async` and `removeValue(_:)` (one value outside a check-in: a value before the opening date moves it back, and the next value's automatic flow is worked out again, a typed one kept; Tracker's `Library.saveValue`, `removeValue`, `editValuations`), `upsert(prices:fxRates:indices:)`, `save(_ plan:)`, `deletePlan` (keeps its projections), `duplicatePlan`, `setMainPlan`, `saveBaseline(_:for:)`, `record(_ headline:for:)`, `updateSettings`, `save(_ profile:)`.
- **Backups:** `backups()`; `backup(paths:label:)` copies files into `backups/<timestamp>-<label>/` after the queued saves; `commit(backingUpAs:_:)` is `commit` with exactly the files the edit changes backed up first, in the same queued operation, and the files as written recorded in the backup after (the import uses it); `undo(_:safetyLabel:)` undoes such an edit and no later one, returning what it left in place (`UndoReport.keptChanges`); `restore(_:)` puts a backup's files back as they were, over later edits, and refuses a backup of another format version.
- **Opening:** `start()` at launch (an existing iCloud library wins, then a local one, else onboarding; iCloud is asked and given a few seconds, so a new device doesn't create a second library), `createLibrary(in:settings:)`, `open(_:)` and `moveToICloud()` (both wait for the queued saves and refuse edits meanwhile), `useLibraryOnThisDevice()`, `reloadAll()`, `refreshFromDisk()` (reloads files whose modification dates changed; the root view calls it when the app becomes active), `waitForPendingWrites()`.
- **Sync:** files changed by the other device or a text editor are reloaded automatically, including a change that landed while the library loaded (only those files' entities are replaced, and never a file with an edit waiting to be saved: that save merges the file and reloads it); sync conflicts are merged record by record and listed in `mergedConflicts`. Show them with `LibraryStatusBanners()` or link to `SyncScreen`.
- `LibraryStore.inMemory(library)` holds a library without files (previews, tests).

### PriceStore — prices, FX and inflation

`fetch(for:on:refresh:) async -> CheckInPrices` (never throws; failures are entries with a readable reason), `fetch(for:on:including:refresh:)` (also instruments the library doesn't hold yet, e.g. a position added in a check-in), `testFetch(_ instrument:baseCurrency:on:) async -> PriceListEntry`, `quote(_ instrument:baseCurrency:on:) async -> CheckInPrices` (one instrument's price and its currency's rate, as records that can be saved: the editor's *Test price fetch*), `fetchEach(_ needs:refresh:received:)` (several fetches at once, each result handed over as it arrives; `refresh` clears the session's cache once first: *Update Prices*), `isFetching`, `canFetch` (false in previews), `lastResult`. API keys come from the Keychain (`KeychainCredentials`, set in Settings).

Prices are saved outside a check-in by the Instruments screen (`Features/Accounts/InstrumentPriceUpdate.swift`): `InstrumentPriceUpdatePlan` (the held instruments with a price source and their currencies), `InstrumentPriceUpdate` (a line per instrument and rate; `settle(in:replacingTyped:)` decides what to save against the library as it is, keeping prices and rates typed in by hand for the date) and `InstrumentPriceUpdater` (fetches with `fetchEach`, saves with one `upsert(prices:fxRates:)`).

### CheckInStore — the check-in in progress

Owns a `Tracker.CheckInDraft`, kept as JSON in `Application Support/<bundle id>/CheckIn/draft.json` until saved, never half-written to the library.

- `begin(on:)` resumes the draft (moved to the date if given) or starts one on the suggested date, then fetches prices into it (unless turned off in Settings). `changeDate(to:)`.
- **Following the library.** The draft is rebased (`CheckInDraft.rebase(onto:)`) when it's resumed, whenever `LibraryStore.revision` changes while it exists (once the library is loaded), and right before saving: rows are refreshed from the current previous and saved valuations, added for new accounts and dropped for deleted or closed ones; what was entered is kept. A value saved on the draft's date elsewhere (the other device) that differs from what was entered becomes the row's `conflict`: it writes nothing until it's settled with `resolveConflict(of:keepingSaved:)` or `resolveConflicts(keepingSaved:)`. `refresh()` rebases by hand.
- Edit: `update { draft in … }`, `updateRow(accountID) { row in row.setBalance(…) }`, `markRestUnchanged()` (accounts without an earlier value are skipped), `setManualPrice(_:for:)`, `setManualFXRate(_:for:)` (typed prices survive re-fetching), `fetchPrices(refresh:)` (the library's instruments and the draft's, so a position added in the check-in is priced; adding one fetches again).
- Read: `draft`, `review` (the new total, waterfall and warnings, from `CheckInDraft.review`), `priceList` (every instrument, rate and index with its source or failure), `isFetchingPrices`, `indices`, `status` (for the accessory: `CheckInStatus` with `summary()`, `isDue`, `hasDraft`, `nextCheckIn`, progress).
- `save() async throws -> CheckInSaveResult` rebases, then writes valuations, prices, FX rates and index values in one `LibraryStore.commit` and waits for the files (moving back the opening date of accounts that open later and got a value, and working out again the automatic flows of values after a past check-in: `CheckInDraft.apply(to:)`). Only then does it delete the draft and ask `PlanStore.checkInSaved(on:)` for this month's answer (`result.headline`), and only when it's the library's latest check-in: a past one (`CheckInStore.laterCheckIn(than:in:)`) records no headline and no baseline, and returns `result.laterCheckIn` (`isPast`). A failed write throws and keeps the draft; conflicts found by the rebase just before writing throw `CheckInStoreError.changedElsewhere` and write nothing. `discard()`, `persistNow()` (the root view calls it when the app leaves the foreground), `restoreDraft()` (at launch), `restore(_:indices:)` (puts a check-in back as the draft).

### PlanStore — runs, results, headlines, baselines

The numbers come from a `PlanEngine` (see `Stores/PlanEngine.swift`). The app uses `PlannerPlanEngine` (`Stores/PlannerPlanEngine.swift`): `Planner.run` with `AppTaxRegistry.standard` (Italy and generic), results cached per plan hash and library inputs. Previews use `PreviewPlanEngine` (made-up but plausible results); `UnavailablePlanEngine` remains for a build without a planner.

- `run(_ plan:mode:whatIf:focusAge:) async -> PlanResults?` runs off the main thread and cancels the previous run of the same plan and kind, or joins it when the request is the same (`mode: .fast` for fewer runs while a slider moves; `whatIf: PlanWhatIf(retirementAge:retiredSpending:monthlySaving:equityReturn:)` for what-ifs, kept apart in `whatIfResults`; `focusAge:` for the charts at another retirement age, in `focusResults`). `scheduleRun(_:after:)` debounces, `cancel(_:)`, `clearWhatIf(_:)`, `cancelWhatIf(_:)`, `clearFocus(_:)`, `isRunning(_:)`, `running`, `errors`.
- `results[planID]`: `PlanResults` — `headline: PlanHeadline` (earliest age and date, confidence, success today and at the target age, sustainable spending, FI progress), `successByAge`, `portfolio` (fan), `markers`, `income`, `taxes`, `spending`, `failure`, what a baseline saves (`start`, `accounts`, `taxParameters`, `years`), and `details` from the Planner (plan hash, FI number, pensions, net income by year, lifetime taxes, the run's warnings, and `headline`, the record written at a check-in, identical to the CLI's; `nil` from the preview engine). All plain values that feed the chart components directly.
- `mainHeadline`: the Overview's answer: the main plan's latest results, or its last recorded headline.
- `checkInSaved(on:)` re-runs the main plan, records its headline (`projections/<plan>/headlines`) and saves the yearly baseline at the year's first check-in. `saveBaseline(for:label:kind:on:)`, `recordedHeadlines(for:)`, `hash(of:)` (a plan's `planHash`, the Planner's).

### Small stores

- `PrivacySettings`: `hidesAmounts` (the eye button and ⌘⇧H), `hideAmountsOnLaunch`, `hideInAppSwitcher` (the root view covers the app while it isn't active), `toggleHidesAmounts()`.
- `AppPreferences` (this device, `UserDefaults`): `libraryLocation`, `stalenessThreshold` (45 days), `fetchPricesOnCheckIn`, `reminder: CheckInReminder?` (scheduled by `ReminderScheduler`).
- `AppNavigation`: `layout` (`.tabs` / `.sidebar`, set by the root view), `tab`, `sidebarSelection`, `accountsPath`, `selectedPlan`, `sheet` (`.settings`, `.newAccount`, `.importFile(url)`, `.welcome`), `isCheckInPresented`, `showsFuture` (the Overview's *Future* switch and ⌘⇧F), `pendingImport`. Navigate with `startCheckIn()`, `finishCheckIn()`, `showOverview()`, `showAccounts(_:)`, `showAccount(_:)`, `showPlan(_:)`, `showSettings()`, `newAccount()`, `startImport(_:)`, `show(_ sidebarItem:)`: they work in both layouts.

## Menu commands

`App/AppCommands.swift`, on the Mac menu bar and iPad: New Account ⌘N, New Check-in ⌘K, Import CSV ⌘⇧I, Hide Amounts ⌘⇧H, Show Future ⌘⇧F, and a **Plan** menu: Save Baseline ⌘⇧B, Duplicate Plan ⌘D, Compare Plans ⌘⌥C. The plan commands act on the plan on screen, which publishes them:

```swift
.focusedSceneValue(\.planActions, PlanCommandActions(saveBaseline: { … }, duplicate: { … }, compare: { … }))
```

Dropping a CSV file anywhere on the window calls `navigation.startImport(file)`.

## Design system

- **Colours** (`Palette`, backed by colour sets in `App/Resources/Assets.xcassets`, light and dark): the asset-class colours in stacking order (`Palette.color(for: assetClass)`: cash blue, bonds orange, equity aqua, gold yellow, crypto magenta, real estate green, other violet, debt red), the categorical `series` slots in fixed order, `accent` (the one hue for everything else), `ink` (actual history and text), `secondaryInk`, `mutedInk`, `gridline`, `axis`, `positive` / `negative` (changes, always with a sign and arrow), status colours (`good`, `warning`, `serious`, `critical`; always with an icon and a label), surfaces (`page`, `card`, `border`). Charts name colours by role with `ChartColor`.
- **Spacing:** `Metrics` (`xs` 4, `s` 8, `m` 12, `l` 16, `xl` 24, `cardRadius`, `lineWidth`, `barRadius`, `readableWidth`). Icons: `AccountKind.systemImage`, `AccountGroup.systemImage`, `AppSymbol`.
- **Numbers** (`AmountFormat`, locale-aware): `amount(_:currency:precision:)` (`.whole` by default, `.cents` in check-in fields and account detail, `.automatic`), `signedAmount`, `percent`, `number`, `compact` (`312k`, `1,2M` for charts), dates (`shortDate` "30 Sep", `mediumDate`, `longDate`, `monthName`). `Decimal.doubleValue` for charts only. `CalendarDate.dateValue` gives a `Date` (noon, local time).
- **Input:** `AmountInput.decimal(from:locale:)` reads `1.234,56`, `1234.56`, `0,4215` and `−240`; `AmountInput.text(for:)` fills a field. `CurrencyChoices` and `CountryChoices` for pickers.
- **Views:** `AmountText(amount, currency:, precision:, tabular:, animatesChanges:)` — tabular figures, `•••••` while amounts are hidden, `.privacySensitive()`. `DeltaText(amount)` / `DeltaText(percent:)` — ▲/▼, sign and colour, `invertsColor` for debts. `Card("Title") { … }`, `Card { … } header: { SectionHeader("Title") { accessory } }`. `StatusBanner(.info/.success/.warning/.error, title, message:, actionTitle:, action:)`. `LibraryStatusBanners()` shows read-only, save errors, unreadable files and merged conflicts. `.tabularFigures()`.
- **Environment values:** `\.baseCurrency` and `\.hidesAmounts`, set by `appEnvironment`; `AmountText` reads them, so you rarely pass a currency.

## Charts

`Components/Charts/`: Swift Charts views that take plain values (`ChartData.swift`), never stores, so they preview with made-up numbers. Thin 2 pt lines, faint gridlines, compact axis labels (hidden while amounts are hidden), direct labels instead of legends where there are few series, drag to read any value (`chartXSelection`), and a VoiceOver summary (`accessibilityChartDescriptor`) on every chart.

| View | Input | Notes |
| --- | --- | --- |
| `NetWorthChart(history:stacked:projection:markers:currency:height:)` | `[ChartPoint]`, `[ChartSeries]`, `[FanPoint]`, `[ChartMarker]` | a line in ink with a light fill, or stacked areas by asset class (debts below zero); optional future: 10–90% band and dashed median; callout on drag |
| `FanChart(fan:actual:markers:currency:height:)` | `[FanPoint]`, `[ChartPoint]` | p10–p90 and p25–p75 bands in one hue, median, actual line in ink, markers |
| `SuccessCurveChart(points:threshold:highlightedAge:selectedAge:)` / `(series:…)` | `[SuccessPoint]` / `[SuccessSeries]` | dotted confidence rule, crossing marked, bind `selectedAge` |
| `IncomeStackChart(segments:spending:currency:height:)` | `[IncomeSegment]`, `[YearValue]` | stacked bars by source (colour per `IncomeSegment.color`), spending as a dashed line; pass tax segments for the *Taxes* view |
| `WaterfallChart(steps:currency:height:)` | `[WaterfallStep]` | `WaterfallStep.steps(for: valueChange)` gives start, markets, new money, other, end |
| `BreakdownBars(rows:currency:limit:)` | `[BreakdownRow]` | horizontal bars with amount and share; `limit` folds the rest into "Other" |
| `Sparkline(points:color:)` | `[ChartPoint]` | no axes; for list rows |

Adapters from Tracker: `[SeriesPoint].chartPoints`, `Breakdown.rows`, `StackedSeries.chartSeries`, `BreakdownKey.chartColor`, `ChartPoint(seriesPoint)`.

## Previews

Every view has a `#Preview`. `.previewEnvironment()` injects in-memory stores holding `PreviewLibrary.library` — a made-up library built in code with the same numbers as the test example library (ten accounts, October 2025 to September 2026, two plans, a baseline, headlines); `.previewEnvironment(PreviewLibrary.empty)` for empty states; `.previewEnvironment(model: AppModel.preview(…))` to set a store up first. Nothing is read, written or fetched. Plans run on `PreviewPlanEngine`; `PreviewResultsView { results in … }` hands a view ready plan results.

## Library location and sync

At launch `LibraryStore.start()` asks `CloudSync.LibraryLocator` for the iCloud container's `Documents/` (off the main thread) or `Application Support/<bundle id>/Library`, remembers the choice on the device, and loads through `CloudSync.LibrarySync`: coordinated reads and atomic writes (`CoordinatedFileAccess`), an `NSMetadataQuery` watcher that also downloads files eagerly (polling for a local library), and conflict merging with `Storage.ConflictResolver` (`NSFileVersion`). A library on this device can be moved to iCloud Drive from Settings. A library written by a newer app opens read-only.

## Not done yet

- **Not built:** separate windows for plan comparison and import on the Mac (add `WindowGroup(id:)` scenes and `openWindow`), Face ID lock (M3), widgets (M3), an app icon (add an `AppIcon` set and set `ASSETCATALOG_COMPILER_APPICON_NAME` in project.yml), and reacting to the iCloud account changing while the app runs.

## Checking without Xcode

The app only builds on a Mac, but everything that doesn't import SwiftUI (the `Stores/` folder, `AppNavigation`, `AmountFormat`, `AmountInput`, `ChartData`, `AppModel`, `PreviewLibrary`, `PreviewPlanEngine`) compiles on Linux too. To type-check and test it there, make a scratch Swift package outside the repository that depends on this one (`Model`, `Tracker`, `Storage`, `Prices`, `CloudSync`), copy those files into a target, and add Swift Testing tests. That's how the stores were tested: loading, editing and saving a copy of the example library, the watcher reloading a hand-edited file, the read-only guard, a full check-in save, plan runs, and `PreviewLibrary` being identical to the example library.

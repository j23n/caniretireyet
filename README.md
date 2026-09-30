# Can I Retire Yet?

A personal net-worth tracker and retirement planner for iPhone and Mac.

- **Track.** Once a month, record what each account and holding is worth: cash, ETFs, crypto, gold, pension funds, property and debts. You can open and close accounts without losing their history.
- **Plan.** Start from your real numbers and project forward: savings, spending, pensions, windfalls and taxes. Taxes come from pluggable tax systems and regimes. Italy is first, including impatriati and forfettario. The app answers the question in its name: *can I retire yet, and if not, when?*
- **Your data is files.** Everything is stored as plain JSON files in a folder in iCloud Drive. The iPhone and Mac apps both read and write that folder, and iCloud keeps it in sync. There is no server, no account to create, and no lock-in.

Status: planning. Start with [docs/PLAN.md](docs/PLAN.md).

| Document | What it covers |
| --- | --- |
| [docs/PLAN.md](docs/PLAN.md) | Scope, key decisions, architecture, milestones, open questions |
| [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md) | The library folder: files, fields, and how sync conflicts are merged |
| [docs/PLANNER.md](docs/PLANNER.md) | The retirement simulation |
| [docs/TAXES.md](docs/TAXES.md) | Pluggable tax systems and regimes: concepts, interfaces, parameter files |
| [docs/tax/IT.md](docs/tax/IT.md) | The Italian tax system: work income, impatriati, INPS, pension fund, investments |
| [docs/IMPORT.md](docs/IMPORT.md) | Importing any spreadsheet or export by mapping its columns |

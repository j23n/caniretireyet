import Testing
@testable import CanIRetireYet

/// What the banner says after the app upgraded the library's format
/// (docs/ACCOUNTS.md, "Settled questions").
struct LibraryUpgradeTests {
    private func upgrade(notes: [String]) -> LibraryUpgrade {
        LibraryUpgrade(fromVersion: 3, toVersion: 4, steps: ["A step."], notes: notes,
                       backupPath: "backups/2026-10-11-v3")
    }

    @Test func saysACopyWasKept() {
        #expect(upgrade(notes: []).message == "This version of the app keeps your library in a newer format, so it "
            + "upgraded it and kept a copy from before.")
        #expect(upgrade(notes: []).backupNote
            == "A copy of the library from before is in backups/2026-10-11-v3, in the library's folder.")
    }

    @Test func countsTheNotes() {
        #expect(upgrade(notes: ["One."]).message.hasSuffix(" A note says what to check."))
        #expect(upgrade(notes: ["One.", "Two."]).message.hasSuffix(" 2 notes say what to check."))
    }
}

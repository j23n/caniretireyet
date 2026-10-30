import Foundation
import Testing
@testable import CanIRetireYet

/// The full-screen check-in on iPhone (UI.md, "Check-in"): it can only be
/// saved or cancelled, so a link or a widget opens nothing while it's
/// unsaved; once it's saved, a link closes it, then opens its place.
@MainActor
struct CheckInNavigationTests {
    private func openCheckIn() -> AppNavigation {
        let navigation = AppNavigation()
        navigation.layout = .tabs
        navigation.startCheckIn()
        return navigation
    }

    @Test func anOpenCheckInKeepsLinksOut() {
        let navigation = openCheckIn()
        navigation.showPlan()
        #expect(navigation.tab == .today)
        #expect(navigation.sidebarSelection == .today)
        navigation.showSoFar()
        #expect(navigation.tab == .today)
        #expect(navigation.soFarOpening == nil)
        navigation.showMonths()
        #expect(navigation.todayPath.isEmpty)
        #expect(navigation.isCheckInPresented)
    }

    @Test func aSavedCheckInClosesForALink() async throws {
        let navigation = openCheckIn()
        navigation.isCheckInSaved = true
        navigation.showPlan()
        #expect(!navigation.isCheckInPresented)
        #expect(!navigation.isCheckInSaved)
        // finishCheckIn(then:) opens the place once the cover has closed.
        let deadline = Date().addingTimeInterval(5)
        while navigation.tab != .ahead, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(navigation.tab == .ahead)
    }
}

import SwiftUI
import WidgetKit

/// The widgets (UI.md, "Widgets"), in the order the gallery lists them. They
/// draw the snapshot the app keeps in the App Group (`Glance`) and never
/// open the library themselves.
@main
struct CanIRetireYetWidgets: WidgetBundle {
    var body: some Widget {
        RetireInWidget()
        NetWorthWidget()
        SinceCheckInWidget()
        ReadinessWidget()
        CheckInWidget()
        EarliestAgeWidget()
        SpendingWidget()
        AllocationWidget()
    }
}

import SwiftUI

/// The check-in's state in one line, and the way into it (UI.md,
/// "Navigation"): "October check-in · due in 3 days", "Last check-in 30 Sep
/// · next 31 Oct", or "Continue check-in · 7 of 9 reviewed". Tapping it
/// opens the check-in.
///
/// It sits in the iPhone tab bar's bottom accessory, which provides the
/// glass; it can also go at the top of a screen.
struct CheckInAccessory: View {
    @Environment(CheckInStore.self) private var checkIn
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.locale) private var locale

    var body: some View {
        let status = checkIn.status
        Button {
            navigation.startCheckIn()
        } label: {
            HStack(spacing: Metrics.s) {
                Image(systemName: status.hasDraft ? "pencil.circle" : status.isDue ? "calendar.badge.clock" : "calendar")
                    .foregroundStyle(status.isDue || status.hasDraft ? Palette.accent : Palette.secondaryInk)
                    .accessibilityHidden(true)
                Text(status.summary(locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: Metrics.xs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.mutedInk)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Metrics.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the check-in")
    }
}

#Preview("Accessory") {
    CheckInAccessory()
        .padding(.vertical)
        .previewEnvironment()
}

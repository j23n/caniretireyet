import CloudSync
import Storage
import SwiftUI

/// A calm status message: an icon, a title and a sentence, with an optional
/// action. Status colours only ever appear with the icon and the words
/// (UI.md, "Status colours"); nothing here scolds.
///
/// `personal` says which of its texts show the person's data, such as an
/// account's name, a date or a file's path: they're
/// `.privacySensitiveInFeedback()`, hidden in a feedback screenshot while the
/// rest of the banner and its action stay (App/README.md, "Feedback").
///
///     StatusBanner(.warning, "Fondo pensione: last value in May", personal: .title)
///     StatusBanner(.info, "Read-only", message: "…", action: ("Learn more", { … }))
struct StatusBanner: View {
    /// The texts that show the person's data.
    struct Personal: OptionSet, Hashable, Sendable {
        let rawValue: Int

        static let title = Personal(rawValue: 1 << 0)
        static let message = Personal(rawValue: 1 << 1)
    }

    enum Kind: Hashable, Sendable {
        case info
        case success
        case warning
        case error

        var systemImage: String {
            switch self {
            case .info: "info.circle"
            case .success: "checkmark.circle"
            case .warning: "exclamationmark.triangle"
            case .error: "xmark.octagon"
            }
        }

        var color: Color {
            switch self {
            case .info: Palette.accent
            case .success: Palette.good
            case .warning: Palette.warning
            case .error: Palette.critical
            }
        }
    }

    let kind: Kind
    let title: String
    var message: String?
    var personal: Personal = []
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ kind: Kind, _ title: String, message: String? = nil, personal: Personal = [], actionTitle: String? = nil,
         action: (() -> Void)? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.personal = personal
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(kind.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .privacySensitiveInFeedback(personal.contains(.title))
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .privacySensitiveInFeedback(personal.contains(.message))
                }
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius / 1.5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius / 1.5, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The library's own state as banners: an upgrade of its format, read-only,
/// a failed save, files that couldn't be read, conflicts that were merged or
/// failed, and files a save copied to backups or kept because they changed
/// elsewhere. Shows nothing when all is well. Screens put it at the top of
/// their content; Today shows it in "Needs attention".
struct LibraryStatusBanners: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    /// What the upgrade did, open in a sheet; closing it dismisses the banner.
    @State private var shownUpgrade: LibraryUpgrade?

    /// Whether there's a banner to show: the body's conditions, for a
    /// screen that shows the banners in a card of its own (Today's
    /// "Needs attention").
    static func showsAny(for library: LibraryStore) -> Bool {
        library.upgrade != nil || library.isReadOnly || library.lastError != nil
            || library.loadIssues.contains { $0.severity == .error }
            || !library.mergedConflicts.isEmpty || !library.conflictFailures.isEmpty || !library.saveNotices.isEmpty
    }

    var body: some View {
        VStack(spacing: Metrics.s) {
            if let upgrade = library.upgrade {
                StatusBanner(.info, LibraryUpgrade.title, message: upgrade.message, actionTitle: "Show details") {
                    shownUpgrade = upgrade
                }
            }
            if let reason = library.readOnlyReason {
                StatusBanner(.info, "Read-only", message: LibraryStoreError.readOnly(reason).message)
            }
            if let error = library.lastError {
                StatusBanner(.error, "Something went wrong with the library", message: error, personal: .message,
                             actionTitle: "Dismiss") { library.dismissError() }
            }
            let errors = library.loadIssues.filter { $0.severity == .error }
            if !errors.isEmpty {
                StatusBanner(
                    .warning, errors.count == 1 ? "A file couldn't be read" : "\(errors.count) files couldn't be read",
                    message: errors.prefix(3).map(\.description).joined(separator: "\n"), personal: .message,
                    actionTitle: "Show details") { navigation.show(.sync) }
            }
            if !library.mergedConflicts.isEmpty {
                let count = library.mergedConflicts.count
                StatusBanner(
                    .info, count == 1 ? "A sync conflict was merged" : "\(count) sync conflicts were merged",
                    message: library.mergedConflicts.first?.summary, personal: .message,
                    actionTitle: "Review") { navigation.show(.sync) }
            }
            if !library.conflictFailures.isEmpty {
                StatusBanner(
                    .warning, "A sync conflict couldn't be merged",
                    message: library.conflictFailures.map(\.path).joined(separator: ", "), personal: .message,
                    actionTitle: "Show details") { navigation.show(.sync) }
            }
            if !library.saveNotices.isEmpty {
                let count = library.saveNotices.count
                StatusBanner(
                    .warning, count == 1 ? "Saving found a file changed elsewhere"
                        : "Saving found \(count) files changed elsewhere",
                    message: library.saveNotices.first?.summary, personal: .message,
                    actionTitle: "Review") { navigation.show(.sync) }
            }
        }
        .sheet(item: $shownUpgrade, onDismiss: { library.dismissUpgrade() }) { upgrade in
            LibraryUpgradeSheet(upgrade: upgrade)
        }
    }
}

#Preview("Banners") {
    VStack(spacing: Metrics.m) {
        StatusBanner(.warning, "Fondo pensione: last value in May", message: "Update it at your next check-in.")
        StatusBanner(.info, "A sync conflict was merged", message: "Merged 2 versions of history for 2026-09.",
                     actionTitle: "Review") {}
        StatusBanner(.error, "Couldn't save your changes", message: "The disk is full.")
        StatusBanner(.success, "Saved")
        StatusBanner(.info, LibraryUpgrade.title, message: LibraryUpgrade.example.message,
                     actionTitle: "Show details") {}
        LibraryStatusBanners()
    }
    .padding()
    .background(Palette.page)
    .previewEnvironment()
}

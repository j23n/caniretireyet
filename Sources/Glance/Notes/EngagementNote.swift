import Foundation
import Model

/// A note the app schedules (UI.md, "Notifications"): when it shows, its
/// words and where tapping it goes. Notes show ages, years and
/// percentages, never amounts.
public struct EngagementNote: Hashable, Sendable, Identifiable {
    /// Which note it is.
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        /// The month's note: the answer and the ask to check in.
        case monthly
        /// The month's note after a month or two without a check-in.
        case catchUp
        /// After three months without a check-in, the note every third month.
        case quarterly
        /// The year in review, on 3 January.
        case yourYear
        case birthday
        /// The anniversary of the first record.
        case recordsAnniversary
        /// A year after the main plan last changed.
        case planCheckUp
    }

    public var kind: Kind
    public var time: NoteTime
    public var title: String
    public var body: String
    /// Where tapping it goes.
    public var link: GlanceLink
    /// Whether it carries the answer's chart when touched and held: the
    /// monthly note that tells the answer.
    public var showsChart: Bool

    public init(kind: Kind, time: NoteTime, title: String, body: String, link: GlanceLink,
                showsChart: Bool = false) {
        self.kind = kind
        self.time = time
        self.title = title
        self.body = body
        self.link = link
        self.showsChart = showsChart
    }

    /// The same for the same kind on the same day: "monthly-2026-10-31".
    public var id: String { "\(kind.rawValue)-\(time.date)" }

    /// Whether it asks for a check-in, so it offers *Import Files*.
    public var asksForCheckIn: Bool {
        switch kind {
        case .monthly, .catchUp, .quarterly: true
        default: false
        }
    }
}

import Foundation

/// Where each appointment and break sits on the day's timeline.
/// Pure and time-zone aware so it can be tested without a view.
struct TimelineLayout: Equatable {
    struct Placement: Identifiable, Equatable {
        let item: ScheduleItem
        /// Minutes from the top of the timeline (`firstHour`).
        let top: Double
        let duration: Double
        /// Overlapping items sit side by side: column `lane` of `lanes`.
        let lane: Int
        let lanes: Int

        var id: String { item.id }
    }

    let firstHour: Int
    let lastHour: Int
    let placements: [Placement]
    /// Items Booker sent without a start time; shown under the timeline.
    let unscheduled: [ScheduleItem]

    static let defaultDuration: Double = 30

    /// - Parameters:
    ///   - day: any instant on the day being shown.
    ///   - calendar: a calendar in the shop's time zone.
    ///   - workingHours: the hours always shown, widened to fit anything outside them.
    init(items: [ScheduleItem], day: Date, calendar: Calendar, workingHours: ClosedRange<Int> = 9...19) {
        let midnight = calendar.startOfDay(for: day)
        func minutes(_ date: Date) -> Double { date.timeIntervalSince(midnight) / 60 }

        let timed = items
            .compactMap { item -> (ScheduleItem, Double, Double)? in
                guard let start = item.start else { return nil }
                let begin = max(0, minutes(start))
                let end = item.end.map { min(24 * 60, minutes($0)) } ?? begin + Self.defaultDuration
                return (item, begin, max(end, begin + 1))
            }
            .sorted { $0.1 < $1.1 || ($0.1 == $1.1 && $0.2 > $1.2) }

        let earliest = timed.map { Int($0.1 / 60) }.min() ?? workingHours.lowerBound
        let latest = timed.map { Int(($0.2 / 60).rounded(.up)) }.max() ?? workingHours.upperBound
        let first = min(workingHours.lowerBound, earliest)
        firstHour = first
        lastHour = min(24, max(workingHours.upperBound, latest))

        // Group overlapping items into clusters, then give each item the first free lane in its cluster.
        var result: [Placement] = []
        var cluster: [(item: ScheduleItem, start: Double, end: Double, lane: Int)] = []
        var clusterEnd = -Double.infinity

        func flush() {
            let lanes = (cluster.map(\.lane).max() ?? 0) + 1
            for entry in cluster {
                result.append(Placement(item: entry.item, top: entry.start - Double(first * 60),
                                            duration: entry.end - entry.start, lane: entry.lane, lanes: lanes))
            }
            cluster.removeAll()
        }

        for (item, start, end) in timed {
            if start >= clusterEnd { flush() }
            var laneEnds: [Int: Double] = [:]
            for entry in cluster { laneEnds[entry.lane] = max(laneEnds[entry.lane] ?? 0, entry.end) }
            let lane = (0...).first { (laneEnds[$0] ?? -.infinity) <= start }!
            cluster.append((item, start, end, lane))
            clusterEnd = max(clusterEnd, end)
        }
        flush()

        placements = result
        unscheduled = items.filter { $0.start == nil }
    }

    var hours: [Int] { Array(firstHour...lastHour) }
}

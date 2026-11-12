import Foundation
import Testing
@testable import Hours

@Suite struct TimelineLayoutTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))! }

    private func item(_ id: Int, _ hour: Int, _ minute: Int, minutes: Int?) -> ScheduleItem {
        let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        var fields: [String: JSONValue] = [
            "ID": .number(Double(id)),
            "StartDateTime": .string("/Date(\(Int64(start.timeIntervalSince1970 * 1000))-0500)/"),
        ]
        if let minutes {
            let end = start.addingTimeInterval(Double(minutes) * 60)
            fields["EndDateTime"] = .string("/Date(\(Int64(end.timeIntervalSince1970 * 1000))-0500)/")
        }
        return ScheduleItem(.object(fields), kind: .appointment, index: id)
    }

    @Test func emptyDayShowsWorkingHours() {
        let layout = TimelineLayout(items: [], day: day, calendar: calendar)
        #expect(layout.firstHour == 9)
        #expect(layout.lastHour == 19)
        #expect(layout.placements.isEmpty)
    }

    @Test func itemsArePlacedInMinutesFromTheFirstHourInTheShopsZone() throws {
        let layout = TimelineLayout(items: [item(1, 10, 30, minutes: 45)], day: day, calendar: calendar)
        let placement = try #require(layout.placements.first)
        #expect(placement.top == 90)
        #expect(placement.duration == 45)
        #expect(placement.lane == 0 && placement.lanes == 1)
    }

    @Test func overlappingItemsShareLanesAndBackToBackOnesDont() {
        let layout = TimelineLayout(items: [
            item(1, 10, 0, minutes: 30),
            item(2, 10, 15, minutes: 45),
            item(3, 10, 30, minutes: 30), // starts as #1 ends, so it reuses lane 0
            item(4, 12, 0, minutes: 30),  // separate cluster
        ], day: day, calendar: calendar)

        let byID = Dictionary(uniqueKeysWithValues: layout.placements.map { ($0.id, $0) })
        #expect(byID["appointment-1"]?.lane == 0)
        #expect(byID["appointment-2"]?.lane == 1)
        #expect(byID["appointment-3"]?.lane == 0)
        #expect(byID["appointment-1"]?.lanes == 2)
        #expect(byID["appointment-4"]?.lane == 0)
        #expect(byID["appointment-4"]?.lanes == 1)
    }

    @Test func earlyAndLateItemsWidenTheRange() {
        let layout = TimelineLayout(items: [item(1, 7, 30, minutes: 30), item(2, 20, 0, minutes: 90)], day: day, calendar: calendar)
        #expect(layout.firstHour == 7)
        #expect(layout.lastHour == 22)
    }

    @Test func missingEndTimeDefaultsToHalfAnHourAndMissingStartIsUnscheduled() throws {
        let noStart = ScheduleItem(.object(["ID": .number(9)]), kind: .appointment, index: 9)
        let layout = TimelineLayout(items: [item(1, 9, 0, minutes: nil), noStart], day: day, calendar: calendar)
        #expect(layout.placements.first?.duration == 30)
        #expect(layout.unscheduled.map(\.id) == ["appointment-9"])
    }
}

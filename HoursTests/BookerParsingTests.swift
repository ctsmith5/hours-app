import Foundation
import Testing
@testable import Hours

@Suite struct BookerParsingTests {
    @Test func wcfDatesAreReadAsUTCMilliseconds() {
        #expect(BookerDate.parse("/Date(1790017200000-0400)/") == Date(timeIntervalSince1970: 1_790_017_200))
        #expect(BookerDate.parse("/Date(1790017200000)/") == Date(timeIntervalSince1970: 1_790_017_200))
        #expect(BookerDate.parse("not a date") == nil)
    }

    @Test(arguments: [
        "2026-11-11T03:24:12.4102421+00:00",
        "2026-11-11T03:24:12.410242+00:00",
        "2026-11-11T03:24:12.410Z",
    ])
    func apiDatesAcceptDotNetPrecision(text: String) throws {
        let date = try #require(APIDate.parse(text))
        #expect(abs(date.timeIntervalSince1970 - 1_794_367_452.41) < 0.001)
    }

    @Test func appointmentSummaryReadsTheFieldsItFinds() throws {
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data("""
        {"ID": 9001,
         "StartDateTime": "/Date(1790017200000-0400)/",
         "EndDateTime": "/Date(1790019000000-0400)/",
         "Customer": {"FirstName": "Sam", "LastName": "Rivera"},
         "AppointmentTreatments": [{"TreatmentName": "Fade"}, {"Treatment": {"Name": "Beard trim"}}],
         "Status": {"Name": "Booked"}}
        """.utf8))

        let item = ScheduleItem(raw, kind: .appointment, index: 0)

        #expect(item.id == "appointment-9001")
        #expect(item.title == "Sam Rivera")
        #expect(item.details == ["Fade", "Beard trim"])
        #expect(item.status == "Booked")
        #expect(item.start == Date(timeIntervalSince1970: 1_790_017_200))
        #expect(item.end == Date(timeIntervalSince1970: 1_790_019_000))
    }

    @Test func unknownShapesStillProduceARow() throws {
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"Something":"else"}"#.utf8))
        let item = ScheduleItem(raw, kind: .breakTime, index: 3)

        #expect(item.title == "Break")
        #expect(item.start == nil)
        #expect(item.id == "breakTime-#3")
    }

    @Test func jsonValueRoundTripsBooleansAndNumbersDistinctly() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":true,"b":1,"c":"x","d":null,"e":[1.5]}"#.utf8))
        #expect(value["a"] == .bool(true))
        #expect(value["b"] == .number(1))
        #expect(value["b"]?.displayText == "1")
        #expect(value["d"] == .null)
        #expect(value["e"]?.arrayValue == [.number(1.5)])
    }
}

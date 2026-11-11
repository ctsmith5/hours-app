import Foundation

/// Booker list responses, passed through by the API as Booker sends them.
/// The item schemas aren't verified yet, so items stay as raw JSON and the
/// summaries below read the fields they can find.
struct BookerList: Decodable, Equatable, Sendable {
    let results: [JSONValue]
    let isSuccess: Bool?

    enum CodingKeys: String, CodingKey {
        case results = "Results"
        case isSuccess = "IsSuccess"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decodeIfPresent([JSONValue].self, forKey: .results) ?? []
        isSuccess = try container.decodeIfPresent(Bool.self, forKey: .isSuccess)
    }
}

/// One appointment or break, read leniently from a Booker item.
struct ScheduleItem: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case appointment, breakTime }

    let id: String
    let kind: Kind
    let start: Date?
    let end: Date?
    let title: String
    let details: [String]
    let status: String?
    let raw: JSONValue

    init(_ raw: JSONValue, kind: Kind, index: Int) {
        self.raw = raw
        self.kind = kind
        id = raw["ID"].flatMap(\.displayText).map { "\(kind)-\($0)" } ?? "\(kind)-#\(index)"
        start = raw.firstDate(of: "StartDateTime", "StartTime", "AppointmentDate", "StartDate")
        end = raw.firstDate(of: "EndDateTime", "EndTime", "EndDate")
        status = raw["Status"]?["Name"]?.stringValue ?? raw["Status"]?.stringValue

        switch kind {
        case .appointment:
            let customer = raw["Customer"]
            let name = [customer?["FirstName"]?.stringValue, customer?["LastName"]?.stringValue]
                .compactMap { $0 }.joined(separator: " ")
            title = name.isEmpty ? "Appointment" : name
            let treatments = raw["AppointmentTreatments"]?.arrayValue ?? raw["AppointmentTreatmentDTOs"]?.arrayValue ?? []
            details = treatments.compactMap {
                $0["TreatmentName"]?.stringValue ?? $0["Treatment"]?["Name"]?.stringValue
            }
        case .breakTime:
            title = raw["Reason"]?.stringValue ?? raw["Name"]?.stringValue ?? "Break"
            details = [raw["Notes"]?.stringValue].compactMap { $0 }.filter { !$0.isEmpty }
        }
    }
}

enum BookerDate {
    /// Parses WCF dates like `/Date(1790017200000-0400)/`. The offset only says which
    /// zone Booker displayed it in; the milliseconds are already UTC. ISO 8601 strings work too.
    static func parse(_ text: String) -> Date? {
        if let match = text.firstMatch(of: /\/Date\((-?\d+)([+-]\d{4})?\)\//), let ms = Double(match.output.1) {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        return APIDate.parse(text)
    }
}

private extension JSONValue {
    func firstDate(of keys: String...) -> Date? {
        for key in keys {
            if let text = self[key]?.stringValue, let date = BookerDate.parse(text) { return date }
        }
        return nil
    }
}

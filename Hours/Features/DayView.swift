import SwiftUI

/// Loads one day of appointments and breaks for the signed-in barber.
@MainActor
@Observable
final class DayModel {
    private(set) var appointments: [ScheduleItem] = []
    private(set) var breaks: [ScheduleItem] = []
    private(set) var isLoading = false
    private(set) var error: String?
    var day: Date = .now

    let timeZone: TimeZone
    private let client: APIClient
    private let session: SessionStore

    init(client: APIClient, session: SessionStore, timeZone: TimeZone) {
        self.client = client
        self.session = session
        self.timeZone = timeZone
    }

    /// The API's `date` parameter: `YYYY-MM-DD` in the shop's time zone.
    var dayParameter: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    func move(byDays days: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        day = calendar.date(byAdding: .day, value: days, to: day) ?? day
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let requested = dayParameter
        do {
            async let appointmentList = client.send(API.appointments(on: requested))
            async let breakList = client.send(API.breaks(on: requested))
            let (a, b) = try await (appointmentList, breakList)
            guard requested == dayParameter else { return } // The day changed while loading.
            appointments = a.results.enumerated().map { ScheduleItem($1, kind: .appointment, index: $0) }.sortedByStart()
            breaks = b.results.enumerated().map { ScheduleItem($1, kind: .breakTime, index: $0) }.sortedByStart()
            error = nil
        } catch {
            session.handle(error)
            self.error = error.localizedDescription
        }
    }
}

private extension [ScheduleItem] {
    func sortedByStart() -> [ScheduleItem] {
        sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }
}

struct DayView: View {
    let me: Me
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            Group {
                if let shop = me.currentShop {
                    DaySchedule(model: DayModel(
                        client: session.client,
                        session: session,
                        timeZone: TimeZone(identifier: shop.timeZone) ?? .current
                    ))
                    .navigationTitle(shop.shopName)
                } else {
                    ContentUnavailableView(
                        "No shop yet",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("\(me.email) isn't linked to a shop. Ask the shop owner to add this email.")
                    )
                    .navigationTitle("Hours")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Text(me.email)
                        Button("Sign out", role: .destructive) { Task { await session.signOut() } }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
        }
    }
}

private struct DaySchedule: View {
    @State var model: DayModel

    var body: some View {
        List {
            Section {
                HStack {
                    Button { model.move(byDays: -1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(model.day.formatted(Date.FormatStyle(date: .complete, time: .omitted, timeZone: model.timeZone)))
                        .font(.headline)
                    Spacer()
                    Button { model.move(byDays: 1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.borderless)
            }

            if let error = model.error {
                Section { Text(error).foregroundStyle(.red) }
            }

            Section("Appointments") {
                if model.appointments.isEmpty {
                    Text(model.isLoading ? "Loading…" : "None").foregroundStyle(.secondary)
                }
                ForEach(model.appointments) { ScheduleRow(item: $0, timeZone: model.timeZone) }
            }

            Section("Breaks") {
                if model.breaks.isEmpty {
                    Text(model.isLoading ? "Loading…" : "None").foregroundStyle(.secondary)
                }
                ForEach(model.breaks) { ScheduleRow(item: $0, timeZone: model.timeZone) }
            }
        }
        .refreshable { await model.load() }
        .task(id: model.dayParameter) { await model.load() }
    }
}

private struct ScheduleRow: View {
    let item: ScheduleItem
    let timeZone: TimeZone

    var body: some View {
        NavigationLink {
            ScrollView {
                Text(item.raw.prettyPrinted)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeRange).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                Text(item.title).font(.body.weight(.medium))
                if !item.details.isEmpty {
                    Text(item.details.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary)
                }
                if let status = item.status {
                    Text(status).font(.caption).foregroundStyle(.tint)
                }
            }
        }
    }

    private var timeRange: String {
        let style = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)
        switch (item.start, item.end) {
        case let (start?, end?): return "\(start.formatted(style)) – \(end.formatted(style))"
        case let (start?, nil): return start.formatted(style)
        default: return "Time unknown"
        }
    }
}

import SwiftUI

/// Loads one day of appointments and breaks for the signed-in barber.
@MainActor
@Observable
final class DayModel {
    private(set) var appointments: [ScheduleItem] = []
    private(set) var breaks: [ScheduleItem] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: String?
    var day: Date = .now

    let calendar: Calendar
    private let client: APIClient
    private let session: SessionStore

    init(client: APIClient, session: SessionStore, timeZone: TimeZone) {
        self.client = client
        self.session = session
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2 // Monday
        self.calendar = calendar
    }

    var timeZone: TimeZone { calendar.timeZone }

    /// The API's `date` parameter: `YYYY-MM-DD` in the shop's time zone.
    var dayParameter: String { Self.parameter(for: day, calendar: calendar) }

    var isToday: Bool { calendar.isDateInToday(day) }

    var layout: TimelineLayout {
        TimelineLayout(items: appointments + breaks, day: day, calendar: calendar)
    }

    /// Monday to Sunday of the week containing `day`.
    var week: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    func move(byDays days: Int) {
        day = calendar.date(byAdding: .day, value: days, to: day) ?? day
    }

    func select(_ date: Date) { day = date }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let requested = dayParameter
        do {
            async let appointmentList = client.send(API.appointments(on: requested))
            async let breakList = client.send(API.breaks(on: requested))
            let (a, b) = try await (appointmentList, breakList)
            guard requested == dayParameter else { return } // The day changed while loading.
            appointments = a.results.enumerated().map { ScheduleItem($1, kind: .appointment, index: $0) }
            breaks = b.results.enumerated().map { ScheduleItem($1, kind: .breakTime, index: $0) }
            error = nil
            hasLoaded = true
        } catch {
            guard requested == dayParameter else { return }
            session.handle(error)
            self.error = error.localizedDescription
        }
    }

    static func parameter(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

struct DayView: View {
    let me: Me
    @Environment(SessionStore.self) private var session

    var body: some View {
        if let shop = me.currentShop {
            DaySchedule(
                model: DayModel(client: session.client, session: session,
                                timeZone: TimeZone(identifier: shop.timeZone) ?? .current),
                shopName: shop.shopName,
                email: me.email
            )
        } else {
            NoShopView(email: me.email)
        }
    }
}

private struct DaySchedule: View {
    @State var model: DayModel
    let shopName: String
    let email: String
    @Environment(SessionStore.self) private var session
    @State private var selected: ScheduleItem?

    var body: some View {
        VStack(spacing: 0) {
            header
            WeekStrip(model: model)
            Rectangle().fill(Theme.line).frame(height: 1)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Timeline(model: model, now: context.date, selected: $selected)
            }
        }
        .background(Theme.paper)
        .safeAreaInset(edge: .top, spacing: 0) { BarberStripe() }
        .task(id: model.dayParameter) { await model.load() }
        .sheet(item: $selected) { item in
            ItemDetail(item: item, timeZone: model.timeZone)
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.paper)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(shopName)
                Text(model.day.formatted(Date.FormatStyle(timeZone: model.timeZone).weekday(.wide)))
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.ink)
                Text(model.day.formatted(Date.FormatStyle(timeZone: model.timeZone).month(.wide).day().year()))
                    .font(Theme.serif(.title3))
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            HStack(spacing: 14) {
                if !model.isToday {
                    Button("Today") { model.select(.now) }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(Capsule().stroke(Theme.brass))
                }
                Menu {
                    Text(email)
                    Button("Sign out", role: .destructive) { Task { await session.signOut() } }
                } label: {
                    Text(String(email.prefix(1)).uppercased())
                        .font(Theme.serif(.headline, weight: .semibold))
                        .foregroundStyle(Theme.buttonText)
                        .frame(width: 36, height: 36)
                        .background(Theme.buttonFill, in: Circle())
                }
                .accessibilityLabel("Account")
            }
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

private struct WeekStrip: View {
    let model: DayModel

    var body: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", days: -7, label: "Previous week")
            ForEach(model.week, id: \.self) { date in
                DayCell(date: date, model: model)
            }
            arrow("chevron.right", days: 7, label: "Next week")
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 10)
    }

    private func arrow(_ symbol: String, days: Int, label: String) -> some View {
        Button { model.move(byDays: days) } label: {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .frame(width: 28, height: 44)
        }
        .foregroundStyle(Theme.muted)
        .accessibilityLabel(label)
    }
}

private struct DayCell: View {
    let date: Date
    let model: DayModel

    var body: some View {
        let isSelected = model.calendar.isDate(date, inSameDayAs: model.day)
        let isToday = model.calendar.isDateInToday(date)
        let style = Date.FormatStyle(timeZone: model.timeZone)

        Button { model.select(date) } label: {
            VStack(spacing: 4) {
                Text(date.formatted(style.weekday(.narrow)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Text(date.formatted(style.day()))
                    .font(Theme.serif(.body, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Theme.buttonText : Theme.ink)
                    .frame(width: 34, height: 34)
                    .background(isSelected ? Theme.buttonFill : .clear, in: Circle())
                Circle()
                    .fill(isToday ? Theme.oxblood : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(style.weekday(.wide).month(.wide).day()))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct Timeline: View {
    let model: DayModel
    let now: Date
    @Binding var selected: ScheduleItem?

    private let hourHeight: CGFloat = 76
    private let gutter: CGFloat = 58

    var body: some View {
        let layout = model.layout

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    summary(layout)

                    ZStack(alignment: .topLeading) {
                        hourGrid(layout)
                        GeometryReader { geometry in
                            let width = geometry.size.width - gutter - 12
                            ForEach(layout.placements) { placement in
                                block(placement, width: width)
                            }
                        }
                        if model.isToday { nowLine(layout) }
                        if model.hasLoaded && layout.placements.isEmpty && model.error == nil {
                            emptyDay
                                .padding(.leading, gutter)
                                .padding(.top, hourHeight * 2)
                        }
                    }
                    .frame(height: CGFloat(layout.lastHour - layout.firstHour) * hourHeight + 24)

                    if !layout.unscheduled.isEmpty { unscheduled(layout.unscheduled) }
                }
                .padding(.bottom, 32)
            }
            .refreshable { await model.load() }
            .onChange(of: model.hasLoaded) { scrollToStart(proxy, layout: model.layout) }
            .onChange(of: model.dayParameter) { scrollToStart(proxy, layout: model.layout) }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func summary(_ layout: TimelineLayout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = model.error {
                FormMessage(text: error)
            }
            HStack(spacing: 6) {
                if model.isLoading { ProgressView().controlSize(.small).tint(Theme.brass) }
                Text(summaryText)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var summaryText: String {
        guard model.hasLoaded else { return "Loading the book…" }
        let count = model.appointments.count
        var parts = [count == 1 ? "1 appointment" : "\(count) appointments"]
        if !model.breaks.isEmpty { parts.append(model.breaks.count == 1 ? "1 break" : "\(model.breaks.count) breaks") }
        if let first = model.appointments.compactMap(\.start).min() {
            parts.append("first at \(first.formatted(timeStyle))")
        }
        return parts.joined(separator: " · ")
    }

    private func hourGrid(_ layout: TimelineLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(layout.hours, id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(hourLabel(hour))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.muted)
                        .frame(width: gutter - 14, alignment: .trailing)
                        .offset(y: -7)
                    VStack(spacing: 0) {
                        Rectangle().fill(Theme.line).frame(height: 1)
                        Spacer()
                        DashedRule().opacity(0.5)
                        Spacer()
                    }
                }
                .frame(height: hour == layout.lastHour ? 1 : hourHeight, alignment: .top)
                .id(hour)
            }
        }
        .padding(.top, 12)
    }

    private func block(_ placement: TimelineLayout.Placement, width: CGFloat) -> some View {
        let laneWidth = width / CGFloat(placement.lanes)
        let height = max(CGFloat(placement.duration) / 60 * hourHeight - 3, 26)
        return Button { selected = placement.item } label: {
            if placement.item.kind == .breakTime {
                BreakBlock(item: placement.item, timeStyle: timeStyle, compact: height < 44)
            } else {
                AppointmentBlock(item: placement.item, timeStyle: timeStyle, compact: height < 52)
            }
        }
        .buttonStyle(.plain)
        .frame(width: laneWidth - 4, height: height)
        .offset(x: gutter + CGFloat(placement.lane) * laneWidth,
                y: 12 + CGFloat(placement.top) / 60 * hourHeight + 1)
    }

    private func nowLine(_ layout: TimelineLayout) -> some View {
        let minutes = now.timeIntervalSince(model.calendar.startOfDay(for: now)) / 60 - Double(layout.firstHour * 60)
        let inRange = minutes >= 0 && minutes <= Double((layout.lastHour - layout.firstHour) * 60)
        return HStack(spacing: 0) {
            Text(now.formatted(timeStyle))
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.oxblood)
                .frame(width: gutter - 10, alignment: .trailing)
                .padding(.trailing, 2)
            Circle().fill(Theme.oxblood).frame(width: 8, height: 8)
            Rectangle().fill(Theme.oxblood).frame(height: 1.5)
        }
        .offset(y: 12 + CGFloat(minutes) / 60 * hourHeight - 4)
        .opacity(inRange ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var emptyDay: some View {
        VStack(spacing: 10) {
            Image(systemName: "scissors")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.brass)
            Text("The book is open.")
                .font(Theme.serif(.title3, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("No appointments on this day.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Theme.paper.opacity(0.92))
    }

    private func unscheduled(_ items: [ScheduleItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("No time listed", color: Theme.muted)
            ForEach(items) { item in
                Button { selected = item } label: {
                    AppointmentBlock(item: item, timeStyle: timeStyle, compact: false)
                        .frame(minHeight: 60)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: Helpers

    private var timeStyle: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .shortened, timeZone: model.timeZone)
    }

    private func hourLabel(_ hour: Int) -> String {
        guard hour < 24, let date = model.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: model.day) else {
            return ""
        }
        return date.formatted(Date.FormatStyle(timeZone: model.timeZone).hour(.defaultDigits(amPM: .abbreviated)))
    }

    private func scrollToStart(_ proxy: ScrollViewProxy, layout: TimelineLayout) {
        let nowHour = model.calendar.component(.hour, from: now)
        let firstItemHour = layout.placements.map { layout.firstHour + Int($0.top / 60) }.min()
        // Today, during the shown hours: open at the current hour. Otherwise at the first booking.
        let nowIsShown = model.isToday && (layout.firstHour..<layout.lastHour).contains(nowHour)
        let target = nowIsShown ? max(layout.firstHour, nowHour - 1) : (firstItemHour ?? layout.firstHour)
        withAnimation { proxy.scrollTo(min(target, layout.lastHour), anchor: .top) }
    }
}

private struct DashedRule: View {
    var body: some View {
        Line()
            .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            .frame(height: 1)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: 0, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

private struct AppointmentBlock: View {
    let item: ScheduleItem
    let timeStyle: Date.FormatStyle
    let compact: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Theme.brass).frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                if compact {
                    HStack(spacing: 6) {
                        Text(item.title).font(Theme.serif(.subheadline, weight: .semibold))
                        if let start = item.start {
                            Text(start.formatted(timeStyle)).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                        }
                    }
                    .lineLimit(1)
                } else {
                    Text(timeRange(item, timeStyle))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                    Text(item.title)
                        .font(Theme.serif(.headline, weight: .semibold))
                        .lineLimit(1)
                    if !item.details.isEmpty {
                        Text(item.details.joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                    }
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, compact ? 4 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.line))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct BreakBlock: View {
    let item: ScheduleItem
    let timeStyle: Date.FormatStyle
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Eyebrow(item.title, color: Theme.navy)
                if compact, let start = item.start {
                    Text(start.formatted(timeStyle)).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                }
            }
            if !compact {
                Text(timeRange(item, timeStyle))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, compact ? 4 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                Theme.navy.opacity(0.06)
                Hatching().stroke(Theme.navy.opacity(0.18), lineWidth: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.navy.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private func timeRange(_ item: ScheduleItem, _ style: Date.FormatStyle) -> String {
    switch (item.start, item.end) {
    case let (start?, end?): "\(start.formatted(style)) – \(end.formatted(style))"
    case let (start?, nil): start.formatted(style)
    default: "Time not listed"
    }
}

private struct ItemDetail: View {
    let item: ScheduleItem
    let timeZone: TimeZone
    @State private var showRaw = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(item.kind == .appointment ? "Appointment" : "Break",
                            color: item.kind == .appointment ? Theme.brass : Theme.navy)
                    Text(item.title)
                        .font(Theme.display(30))
                        .foregroundStyle(Theme.ink)
                    Text(timeRange(item, Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)))
                        .font(Theme.serif(.title3))
                        .foregroundStyle(Theme.muted)
                }

                OrnamentRule(width: 120)

                if !item.details.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(item.kind == .appointment ? "Services" : "Notes", color: Theme.muted)
                        ForEach(item.details, id: \.self) { Text($0).foregroundStyle(Theme.ink) }
                    }
                }
                if let status = item.status {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow("Status", color: Theme.muted)
                        Text(status).foregroundStyle(Theme.ink)
                    }
                }

                DisclosureGroup(isExpanded: $showRaw) {
                    Text(item.raw.prettyPrinted)
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
                } label: {
                    Eyebrow("Booker data", color: Theme.muted)
                }
                .tint(Theme.muted)
            }
            .padding(24)
        }
    }
}

private struct NoShopView: View {
    let email: String
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "chair")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.brass)
            Text("No chair yet.")
                .font(Theme.display(30))
                .foregroundStyle(Theme.ink)
            OrnamentRule(width: 110)
            Text("\(email) isn't linked to a shop. Ask the shop owner to add this email, then sign in again.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            Spacer()
            Button("Sign out") { Task { await session.signOut() } }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .safeAreaInset(edge: .top, spacing: 0) { BarberStripe() }
    }
}

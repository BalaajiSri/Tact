import Foundation

enum TrackerMode: String, Codable, CaseIterable, Identifiable {
    case countdown = "Until a date"
    case recurring = "Recurring"
    case elapsed = "Time since"
    case progress = "Date range"

    var id: Self { self }
}

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case weekly = "Selected weekdays"
    case daily = "Every N days"
    case monthlyWorkday = "Working day of the month"
    case monthlyDay = "Day of the month"
    case firstWorkday = "First working day"
    case lastWorkday = "Last working day"
    case ordinalWeekday = "Weekday of the month"
    case yearly = "Same date each year"

    var id: Self { self }
}

enum WeekendRule: String, Codable, CaseIterable, Identifiable {
    case unchanged = "Keep the date"
    case previous = "Previous working day"
    case next = "Next working day"

    var id: Self { self }
}

struct Tracker: Codable, Identifiable {
    var id = UUID()
    var name = ""
    var icon = "calendar"
    var color = "indigo"
    var mode = TrackerMode.countdown
    var start = Date()
    var end = Date()
    var repeatRule = RepeatRule.lastWorkday
    var weekendRule = WeekendRule.unchanged
    var monthDay = 25
    var ordinal = 2
    var weekday = 6
    var showPercentage = false
    var dateOverride: DateOverride?
    var paletteID: Int?
    var swatchIndex: Int?
    var customAccent: String?
    var tinted: Bool?
    var milestones: [Int]?
    var weekdays: [Int]?
    var dayInterval: Int?
    var excludedDates: [Date]?
    var cardStyle: String?
    var backgroundHex: String?
    var textHex: String?
    var remainingHex: String?

    func eventDates(from date: Date, count: Int = 6, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: date)
        switch mode {
        case .countdown, .progress:
            let target = calendar.startOfDay(for: end)
            return target >= today ? [target] : []
        case .elapsed:
            return Array(Set(milestones ?? []).filter { $0 > 0 }.sorted()
                .compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: start)) }
                .filter { $0 >= today }.prefix(count))
        case .recurring:
            return upcoming(from: date, count: count, calendar: calendar)
        }
    }

    struct DateOverride: Codable {
        let original: Date
        let replacement: Date
    }

    struct Reading {
        let value: String
        let detail: String
        let fraction: Double?
        var totalDays: Int? = nil
        var elapsedDays: Int? = nil
    }

    func reading(on date: Date, calendar: Calendar = .current) -> Reading {
        let today = calendar.startOfDay(for: date)
        let anchor = calendar.startOfDay(for: start)
        let target = calendar.startOfDay(for: end)
        switch mode {
        case .countdown:
            let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
            return Reading(value: days < 0 ? "Past" : Self.countdown(days),
                           detail: target.formatted(date: .abbreviated, time: .omitted), fraction: nil)
        case .elapsed:
            let days = calendar.dateComponents([.day], from: anchor, to: today).day ?? 0
            return Reading(value: days < 0 ? "Upcoming" : Self.daysLabel(days),
                           detail: "Since " + anchor.formatted(date: .abbreviated, time: .omitted),
                           fraction: (milestones ?? []).filter { $0 > 0 && $0 >= days }.min()
                               .map { min(1, max(0, Double(days) / Double($0))) })
        case .progress:
            let fraction = Self.fraction(from: anchor, through: today, to: target, calendar: calendar)
            return Reading(value: "\(Int(fraction * 100))%",
                           detail: "Ends " + target.formatted(date: .abbreviated, time: .omitted),
                           fraction: fraction)
        case .recurring:
            let dates = occurrences(around: today, calendar: calendar)
            guard let next = dates.first(where: { $0 >= today }) else {
                return Reading(value: "No date", detail: repeatRule.rawValue, fraction: nil)
            }
            let previous = dates.last { $0 < next }
            let fraction = previous.map { Self.fraction(from: $0, through: today, to: next, calendar: calendar) }
            let days = calendar.dateComponents([.day], from: today, to: next).day ?? 0
            return Reading(value: days == 0 ? "Today" : showPercentage && fraction != nil
                           ? "\(Int((fraction ?? 0) * 100))%" : Self.countdown(days),
                           detail: next.formatted(date: .abbreviated, time: .omitted), fraction: fraction,
                           totalDays: previous.flatMap { calendar.dateComponents([.day], from: $0, to: next).day },
                           elapsedDays: previous.flatMap { calendar.dateComponents([.day], from: $0, to: today).day })
        }
    }

    func upcoming(from date: Date, count: Int = 3, calendar: Calendar = .current) -> [Date] {
        Array(occurrences(around: date, calendar: calendar)
            .filter { $0 >= calendar.startOfDay(for: date) }.prefix(count))
    }

    private func occurrences(around date: Date, calendar: Calendar) -> [Date] {
        if repeatRule == .daily {
            let today = calendar.startOfDay(for: date)
            let anchor = calendar.startOfDay(for: start)
            let interval = max(1, dayInterval ?? 1)
            let offset = calendar.dateComponents([.day], from: anchor, to: today).day ?? 0
            let cycle = Int(floor(Double(offset) / Double(interval)))
            return (-3...100).compactMap { step in
                guard let day = calendar.date(byAdding: .day, value: (cycle + step) * interval, to: anchor) else { return nil }
                if let dateOverride, calendar.isDate(dateOverride.original, inSameDayAs: day) {
                    return calendar.startOfDay(for: dateOverride.replacement)
                }
                return day
            }.sorted()
        }
        if repeatRule == .weekly {
            let today = calendar.startOfDay(for: date)
            let selected = Set((weekdays ?? [weekday]).filter { (1...7).contains($0) })
            return (-14...100).compactMap { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      selected.contains(calendar.component(.weekday, from: day)) else { return nil }
                if let dateOverride, calendar.isDate(dateOverride.original, inSameDayAs: day) {
                    return calendar.startOfDay(for: dateOverride.replacement)
                }
                return day
            }.sorted()
        }
        let yearly = repeatRule == .yearly
        let component: Calendar.Component = yearly ? .year : .month
        guard let periodStart = calendar.dateInterval(of: component, for: date)?.start else { return [] }
        let dates = (-3...6).compactMap { offset -> Date? in
            guard let period = calendar.date(byAdding: component, value: offset, to: periodStart),
                  let scheduled = occurrence(in: period, calendar: calendar) else { return nil }
            if let dateOverride, calendar.isDate(dateOverride.original, inSameDayAs: scheduled) {
                return calendar.startOfDay(for: dateOverride.replacement)
            }
            return scheduled
        }
        return Set(dates).sorted()
    }

    private func occurrence(in period: Date, calendar: Calendar) -> Date? {
        var month = period
        if repeatRule == .yearly {
            let monthOffset = calendar.component(.month, from: end) - 1
            guard let annualMonth = calendar.date(byAdding: .month, value: monthOffset, to: period) else { return nil }
            month = annualMonth
        }
        guard let count = calendar.range(of: .day, in: .month, for: month)?.count else { return nil }
        func day(_ number: Int) -> Date? {
            calendar.date(byAdding: .day, value: number - 1, to: month)
        }
        switch repeatRule {
        case .weekly, .daily:
            return nil
        case .monthlyWorkday:
            let matching = (1...count).compactMap(day).filter { isWorkday($0, calendar: calendar) }
            if ordinal == -1 { return matching.last }
            return matching.indices.contains(ordinal - 1) ? matching[ordinal - 1] : nil
        case .monthlyDay:
            guard let nominal = day(min(count, max(1, monthDay))) else { return nil }
            switch weekendRule {
            case .unchanged: return nominal
            case .previous: return workday(from: nominal, direction: -1, calendar: calendar)
            case .next: return workday(from: nominal, direction: 1, calendar: calendar)
            }
        case .firstWorkday:
            return workday(from: month, direction: 1, calendar: calendar)
        case .lastWorkday:
            return day(count).flatMap { workday(from: $0, direction: -1, calendar: calendar) }
        case .ordinalWeekday:
            let matching = (1...count).compactMap(day).filter { calendar.component(.weekday, from: $0) == weekday }
            let selected = ordinal == -1 ? matching.last :
                (matching.indices.contains(ordinal - 1) ? matching[ordinal - 1] : nil)
            guard let selected, !isWorkday(selected, calendar: calendar) else { return selected }
            switch weekendRule {
            case .unchanged: return selected
            case .previous: return workday(from: selected, direction: -1, calendar: calendar)
            case .next: return workday(from: selected, direction: 1, calendar: calendar)
            }
        case .yearly:
            return day(min(count, calendar.component(.day, from: end)))
        }
    }

    private func workday(from date: Date, direction: Int, calendar: Calendar) -> Date? {
        for offset in 0..<370 {
            guard let candidate = calendar.date(byAdding: .day, value: direction * offset, to: date) else { return nil }
            if isWorkday(candidate, calendar: calendar) { return candidate }
        }
        return nil
    }

    private func isWorkday(_ date: Date, calendar: Calendar) -> Bool {
        let day = calendar.component(.weekday, from: date)
        return (2...6).contains(day) &&
            !(excludedDates ?? []).contains { calendar.isDate($0, inSameDayAs: date) }
    }

    private static func fraction(from start: Date, through today: Date, to target: Date, calendar: Calendar) -> Double {
        let total = calendar.dateComponents([.day], from: start, to: target).day ?? 0
        let elapsed = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        return total > 0 ? min(1, max(0, Double(elapsed) / Double(total))) : 0
    }

    private static func countdown(_ days: Int) -> String {
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "\(daysLabel(days)) left"
    }

    private static func daysLabel(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }
}

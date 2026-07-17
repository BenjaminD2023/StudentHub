import Foundation
import SwiftUI

struct Course: Codable, Hashable, Identifiable {
    let id: String
    var title: String
    var colorHex: UInt32

    static let chemistry = Course(id: "chemistry", title: "Chemistry", colorHex: 0xF5B824)
    static let calculus = Course(id: "calculus", title: "AP Calculus", colorHex: 0x428CFA)
    static let debate = Course(id: "debate", title: "Debate", colorHex: 0x33BDC7)
    static let personal = Course(id: "personal", title: "Personal", colorHex: 0x6EC763)
    static let general = Course(id: "general", title: "General", colorHex: 0x8A8F98)
    static let allCases: [Course] = [.chemistry, .calculus, .debate, .personal, .general]
    static let colorChoices: [UInt32] = [
        0x428CFA, 0x33BDC7, 0x6EC763, 0xF5B824, 0xEF6B73,
        0xA978F2, 0xF08B43, 0x5E9C76, 0x8892A6, 0xD85AA6
    ]

    var rawValue: String { id }
    var accent: Color { Self.color(for: colorHex) }

    init(id: String = UUID().uuidString.lowercased(), title: String, colorHex: UInt32) {
        self.id = id
        self.title = title
        self.colorHex = colorHex
    }

    static func color(for hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static func == (lhs: Course, rhs: Course) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case colorHex
    }

    init(from decoder: Decoder) throws {
        if let legacy = try? decoder.singleValueContainer().decode(String.self) {
            self = Self.builtIn(id: legacy) ?? Course(title: legacy.capitalized, colorHex: 0x8A8F98)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        colorHex = try container.decode(UInt32.self, forKey: .colorHex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(colorHex, forKey: .colorHex)
    }

    private static func builtIn(id: String) -> Course? {
        allCases.first(where: { $0.id == id })
    }
}

struct HubTask: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var course: Course
    var dueDate: Date
    var isCompleted: Bool
    var scheduledHour: Double?
    var projectID: UUID?
    var parentTaskID: UUID?
    var linkedNoteID: UUID?
    var project: String?
    var linkedNote: String?
    var details: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        course: Course,
        dueDate: Date,
        isCompleted: Bool = false,
        scheduledHour: Double? = nil,
        projectID: UUID? = nil,
        parentTaskID: UUID? = nil,
        linkedNoteID: UUID? = nil,
        project: String? = nil,
        linkedNote: String? = nil,
        details: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.course = course
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.scheduledHour = scheduledHour
        self.projectID = projectID
        self.parentTaskID = parentTaskID
        self.linkedNoteID = linkedNoteID
        self.project = project
        self.linkedNote = linkedNote
        self.details = details
        self.createdAt = createdAt
    }

    var dueTimeLabel: String {
        dueDate.formatted(date: .omitted, time: .shortened)
    }
}

struct ScheduleBlock: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var subtitle: String
    var course: Course
    var startHour: Double
    var duration: Double
    var date: Date
    var linkedTaskID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        course: Course,
        startHour: Double,
        duration: Double,
        date: Date = Date(),
        linkedTaskID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.course = course
        self.startHour = startHour
        self.duration = duration
        self.date = date
        self.linkedTaskID = linkedTaskID
    }
}

struct QuickCommandDraft: Equatable {
    var title: String
    var course: Course
    var dueDate: Date
    var linkedNote: String?
    var recognizedTokens: [CommandToken] = []
}

struct CommandToken: Equatable, Identifiable {
    enum Kind: String {
        case date
        case time
        case course
    }

    let kind: Kind
    let text: String

    var id: String { "\(kind.rawValue):\(text)" }

    var icon: String {
        switch kind {
        case .date: "calendar"
        case .time: "clock"
        case .course: "tag"
        }
    }
}

enum CommandIntent: Equatable {
    case createTask
    case rescheduleTask(query: String)
    case search(query: String)
}

struct CommandInterpretation: Equatable {
    let intent: CommandIntent
    let draft: QuickCommandDraft

    var summary: String {
        switch intent {
        case .createTask: "Create a new task"
        case .rescheduleTask(let query): "Reschedule “\(query)”"
        case .search(let query): "Search tasks for “\(query)”"
        }
    }
}

enum CommandInterpreter {
    static func interpret(_ input: String, now: Date = Date(), calendar: Calendar = .current, spaces: [Course] = Course.allCases) -> CommandInterpretation {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let draft = CommandParser.parse(trimmed, now: now, calendar: calendar, spaces: spaces)

        if let target = rescheduleTarget(in: trimmed) {
            return CommandInterpretation(intent: .rescheduleTask(query: target), draft: draft)
        }
        if lowered.hasPrefix("find ") || lowered.hasPrefix("search ") {
            let query = String(trimmed.dropFirst(lowered.hasPrefix("find ") ? 5 : 7))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return CommandInterpretation(intent: .search(query: query), draft: draft)
        }
        return CommandInterpretation(intent: .createTask, draft: draft)
    }

    private static func rescheduleTarget(in input: String) -> String? {
        let lowered = input.lowercased()
        for prefix in ["move ", "reschedule "] where lowered.hasPrefix(prefix) {
            let remainder = String(input.dropFirst(prefix.count))
            if let range = remainder.range(of: " to ", options: [.caseInsensitive, .backwards]) {
                let target = remainder[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                return target.isEmpty ? nil : target
            }
            if let range = remainder.range(of: " for ", options: [.caseInsensitive, .backwards]) {
                let target = remainder[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                return target.isEmpty ? nil : target
            }
        }

        let chinesePatterns = ["移到", "改到", "安排到"]
        for marker in chinesePatterns where input.contains(marker) {
            let before = input.components(separatedBy: marker)[0]
                .replacingOccurrences(of: "把", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return before.isEmpty ? nil : before
        }
        return nil
    }
}

enum CommandParser {
    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current, spaces: [Course] = Course.allCases) -> QuickCommandDraft {
        let lowered = input.lowercased()
        let fallback = spaces.first(where: { $0.id == Course.general.id }) ?? spaces.first ?? .general
        let aliases = [("debate", Course.debate.id), ("calc", Course.calculus.id), ("chem", Course.chemistry.id)]
        let aliasMatch = aliases.first(where: { lowered.contains($0.0) })
            .flatMap { alias in spaces.first(where: { $0.id == alias.1 }) }
        let namedMatch = spaces
            .sorted { $0.title.count > $1.title.count }
            .first(where: { lowered.contains($0.title.lowercased()) || lowered.contains("#\($0.id.lowercased())") })
        let course = aliasMatch ?? namedMatch ?? fallback

        var recognizedTokens: [CommandToken] = []
        var dueDay = now

        if let dateMatch = dateMatch(in: input, now: now, calendar: calendar) {
            dueDay = dateMatch.date
            recognizedTokens.append(CommandToken(kind: .date, text: dateMatch.label))
        }

        var hour = lowered.contains("tonight") || input.contains("今晚") ? 20 : 19
        var minute = lowered.contains("tonight") || input.contains("今晚") ? 0 : 30
        if let twelveHour = firstMatch(#"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#, in: lowered),
           var parsedHour = Int(twelveHour.groups[0]) {
            minute = Int(twelveHour.groups[1]) ?? 0
            let meridiem = twelveHour.groups[2]
            if meridiem == "pm", parsedHour < 12 { parsedHour += 12 }
            if meridiem == "am", parsedHour == 12 { parsedHour = 0 }
            hour = min(max(parsedHour, 0), 23)
            recognizedTokens.append(CommandToken(kind: .time, text: twelveHour.full))
        } else if let twentyFourHour = firstMatch(#"(?<![-/\d])([01]?\d|2[0-3]):([0-5]\d)\b"#, in: lowered),
                  let parsedHour = Int(twentyFourHour.groups[0]), let parsedMinute = Int(twentyFourHour.groups[1]) {
            hour = parsedHour
            minute = parsedMinute
            recognizedTokens.append(CommandToken(kind: .time, text: twentyFourHour.full))
        } else if let chineseTime = firstMatch(#"(上午|中午|下午|晚上)?\s*(\d{1,2})(?:(?:[:点时](\d{1,2})?\s*分?)|点半)"#, in: input),
                  var parsedHour = Int(chineseTime.groups[1]) {
            minute = chineseTime.full.contains("半") ? 30 : (Int(chineseTime.groups[2]) ?? 0)
            if ["下午", "晚上"].contains(chineseTime.groups[0]), parsedHour < 12 { parsedHour += 12 }
            if chineseTime.groups[0] == "中午", parsedHour < 11 { parsedHour += 12 }
            hour = min(max(parsedHour, 0), 23)
            recognizedTokens.append(CommandToken(kind: .time, text: chineseTime.full))
        } else if let simpleHour = firstMatch(#"\b(?:at|to)\s+(\d{1,2})(?:\s*o'clock)?\b"#, in: lowered),
                  var parsedHour = Int(simpleHour.groups[0]), parsedHour <= 23 {
            if parsedHour <= 7 { parsedHour += 12 }
            hour = parsedHour
            minute = 0
            recognizedTokens.append(CommandToken(kind: .time, text: simpleHour.full))
        }

        if course != .general {
            recognizedTokens.append(CommandToken(kind: .course, text: course.title))
        }

        let dueDate = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: dueDay
        ) ?? dueDay

        var title = input
        for token in recognizedTokens where token.kind != .course {
            title = title.replacingOccurrences(of: token.text, with: "", options: [.caseInsensitive])
        }
        title = title.replacingOccurrences(of: #"(?i)^\s*(?:add|create|task|move|reschedule)\s+"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"\s+#\w+"#, with: "", options: .regularExpression)
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingConnector = #"(?i)(?:\s+|^)(?:due|by|on|at|for|to|in)\s*$"#
        while title.range(of: trailingConnector, options: .regularExpression) != nil {
            title = title.replacingOccurrences(of: trailingConnector, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let first = title.first {
            title.replaceSubrange(title.startIndex...title.startIndex, with: String(first).uppercased())
        }

        return QuickCommandDraft(
            title: title.isEmpty ? "Untitled task" : title,
            course: course,
            dueDate: dueDate,
            linkedNote: course.id == Course.chemistry.id ? "Lab Notes.md" : nil,
            recognizedTokens: recognizedTokens
        )
    }

    private static func dateMatch(in input: String, now: Date, calendar: Calendar) -> (date: Date, label: String)? {
        let lowered = input.lowercased()

        if let chineseFull = firstMatch(#"(20\d{2})年(\d{1,2})月(\d{1,2})日?"#, in: input),
           let year = Int(chineseFull.groups[0]), let month = Int(chineseFull.groups[1]), let day = Int(chineseFull.groups[2]),
           let date = validDate(year: year, month: month, day: day, calendar: calendar) {
            return (date, chineseFull.full)
        }

        if let iso = firstMatch(#"\b(20\d{2})[-/](\d{1,2})[-/](\d{1,2})\b"#, in: input),
           let year = Int(iso.groups[0]), let month = Int(iso.groups[1]), let day = Int(iso.groups[2]),
           let date = validDate(year: year, month: month, day: day, calendar: calendar) {
            return (date, iso.full)
        }

        if let chinese = firstMatch(#"(?<!\d)(\d{1,2})月(\d{1,2})日?"#, in: input),
           let month = Int(chinese.groups[0]), let day = Int(chinese.groups[1]),
           let date = nextAnnualDate(month: month, day: day, now: now, calendar: calendar) {
            return (date, chinese.full)
        }

        if let numeric = firstMatch(#"(?<!\d)(\d{1,2})/(\d{1,2})(?:/(20\d{2}))?(?!\d)"#, in: input),
           let month = Int(numeric.groups[0]), let day = Int(numeric.groups[1]) {
            if let year = Int(numeric.groups[2]), let date = validDate(year: year, month: month, day: day, calendar: calendar) {
                return (date, numeric.full)
            }
            if let date = nextAnnualDate(month: month, day: day, now: now, calendar: calendar) {
                return (date, numeric.full)
            }
        }

        if let named = namedMonthMatch(in: input, now: now, calendar: calendar) {
            return named
        }

        if let offset = firstMatch(#"(?i)\bin\s+(\d+)\s+(day|days|week|weeks)\b"#, in: input),
           let value = Int(offset.groups[0]) {
            let component: Calendar.Component = offset.groups[1].lowercased().hasPrefix("week") ? .weekOfYear : .day
            return (calendar.date(byAdding: component, value: value, to: now) ?? now, offset.full)
        }

        if let chineseOffset = firstMatch(#"(?<!\d)(\d+)\s*(天|周|星期)后"#, in: input),
           let value = Int(chineseOffset.groups[0]) {
            let component: Calendar.Component = chineseOffset.groups[1] == "天" ? .day : .weekOfYear
            return (calendar.date(byAdding: component, value: value, to: now) ?? now, chineseOffset.full)
        }

        if lowered.contains("day after tomorrow") || input.contains("后天") {
            let label = input.contains("后天") ? "后天" : matchedText(#"(?i)day after tomorrow"#, in: input, fallback: "day after tomorrow")
            return (calendar.date(byAdding: .day, value: 2, to: now) ?? now, label)
        }
        if lowered.contains("tomorrow") || input.contains("明天") {
            let label = input.contains("明天") ? "明天" : matchedText(#"(?i)tomorrow"#, in: input, fallback: "tomorrow")
            return (calendar.date(byAdding: .day, value: 1, to: now) ?? now, label)
        }
        if lowered.contains("today") || lowered.contains("tonight") || input.contains("今天") || input.contains("今晚") {
            if input.contains("今晚") { return (now, "今晚") }
            if input.contains("今天") { return (now, "今天") }
            let word = lowered.contains("tonight") ? "tonight" : "today"
            return (now, matchedText("(?i)\(word)", in: input, fallback: word))
        }

        if let chineseWeekday = chineseWeekdayMatch(in: input, now: now, calendar: calendar) {
            return chineseWeekday
        }
        if let weekday = weekdayMatch(in: input, after: now, calendar: calendar) {
            return weekday
        }

        if let nextWeek = firstMatch(#"(?i)\bnext week\b"#, in: input) {
            return (calendar.date(byAdding: .weekOfYear, value: 1, to: now) ?? now, nextWeek.full)
        }
        if let weekend = firstMatch(#"(?i)\b(?:this\s+)?weekend\b"#, in: input) {
            var components = DateComponents()
            components.weekday = 7
            return (calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now, weekend.full)
        }
        return nil
    }

    private static func namedMonthMatch(in input: String, now: Date, calendar: Calendar) -> (date: Date, label: String)? {
        let monthNames = "january|jan|february|feb|march|mar|april|apr|may|june|jun|july|jul|august|aug|september|sep|sept|october|oct|november|nov|december|dec"
        let monthFirst = "(?i)\\b(\(monthNames))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(20\\d{2}))?\\b"
        if let match = firstMatch(monthFirst, in: input),
           let month = monthNumber(match.groups[0]), let day = Int(match.groups[1]),
           let date = dateWithOptionalYear(month: month, day: day, yearText: match.groups[2], now: now, calendar: calendar) {
            return (date, match.full)
        }

        let dayFirst = "(?i)\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(\(monthNames))\\.?(?:,?\\s+(20\\d{2}))?\\b"
        if let match = firstMatch(dayFirst, in: input),
           let day = Int(match.groups[0]), let month = monthNumber(match.groups[1]),
           let date = dateWithOptionalYear(month: month, day: day, yearText: match.groups[2], now: now, calendar: calendar) {
            return (date, match.full)
        }
        return nil
    }

    private static func dateWithOptionalYear(month: Int, day: Int, yearText: String, now: Date, calendar: Calendar) -> Date? {
        if let year = Int(yearText) { return validDate(year: year, month: month, day: day, calendar: calendar) }
        return nextAnnualDate(month: month, day: day, now: now, calendar: calendar)
    }

    private static func nextAnnualDate(month: Int, day: Int, now: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: now)
        guard let date = validDate(year: year, month: month, day: day, calendar: calendar) else { return nil }
        if date < calendar.startOfDay(for: now) {
            return validDate(year: year + 1, month: month, day: day, calendar: calendar)
        }
        return date
    }

    private static func validDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard parts.year == year, parts.month == month, parts.day == day else { return nil }
        return date
    }

    private static func monthNumber(_ name: String) -> Int? {
        let key = String(name.lowercased().prefix(3))
        return ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12][key]
    }

    private static func matchedText(_ pattern: String, in input: String, fallback: String) -> String {
        firstMatch(pattern, in: input)?.full ?? fallback
    }

    private static func chineseWeekdayMatch(in input: String, now: Date, calendar: Calendar) -> (date: Date, label: String)? {
        guard let match = firstMatch(#"(下周|下星期|本周|这周|周|星期)([一二三四五六日天])"#, in: input) else { return nil }
        let weekdayMap = ["日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7]
        guard let weekday = weekdayMap[match.groups[1]] else { return nil }
        let prefix = match.groups[0]

        if prefix == "下周" || prefix == "下星期" || prefix == "本周" || prefix == "这周" {
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
            let weekOffset = (prefix == "下周" || prefix == "下星期") ? 1 : 0
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: interval.start) else { return nil }
            let dayOffset = (weekday - calendar.firstWeekday + 7) % 7
            var date = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) ?? now
            if date < calendar.startOfDay(for: now) { date = calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date }
            return (date, match.full)
        }

        var components = DateComponents()
        components.weekday = weekday
        let date = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now
        return (date, match.full)
    }

    private static func firstMatch(_ pattern: String, in source: String) -> (full: String, groups: [String])? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let fullRange = Range(match.range(at: 0), in: source) else { return nil }
        let groups = (1..<match.numberOfRanges).map { index -> String in
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: source) else { return "" }
            return String(source[range])
        }
        return (String(source[fullRange]), groups)
    }

    private static func weekdayMatch(in source: String, after now: Date, calendar: Calendar) -> (date: Date, label: String)? {
        let weekdays = [
            ("sun(?:day)?", 1), ("mon(?:day)?", 2), ("tue(?:s(?:day)?)?", 3),
            ("wed(?:nesday)?", 4), ("thu(?:rs(?:day)?)?", 5),
            ("fri(?:day)?", 6), ("sat(?:urday)?", 7)
        ]
        for (namePattern, value) in weekdays {
            let pattern = #"(?i)\b((?:next|this)\s+)?"# + namePattern + #"\b"#
            guard let match = firstMatch(pattern, in: source) else { continue }
            var components = DateComponents()
            components.weekday = value
            let date = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) ?? now
            return (date, match.full)
        }
        return nil
    }
}

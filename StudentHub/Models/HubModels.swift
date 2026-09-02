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

enum RecurrenceRule: String, CaseIterable, Identifiable, Codable, Hashable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Every day"
        case .weekly: "Every week"
        case .monthly: "Every month"
        }
    }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .daily: calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly: calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly: calendar.date(byAdding: .month, value: 1, to: date)
        }
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
    var estimatedMinutes: Int?
    var details: String
    var createdAt: Date
    var recurrence: RecurrenceRule?
    var nextOccurrenceID: UUID?

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
        estimatedMinutes: Int? = 30,
        details: String = "",
        createdAt: Date = Date(),
        recurrence: RecurrenceRule? = nil,
        nextOccurrenceID: UUID? = nil
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
        self.estimatedMinutes = estimatedMinutes
        self.details = details
        self.createdAt = createdAt
        self.recurrence = recurrence
        self.nextOccurrenceID = nextOccurrenceID
    }

    var dueTimeLabel: String {
        dueDate.formatted(date: .omitted, time: .shortened)
    }

    var estimatedDurationLabel: String? {
        estimatedMinutes.flatMap { $0 > 0 ? $0.studyDurationLabel : nil }
    }
}

extension Int {
    var studyDurationLabel: String {
        guard self >= 60 else { return "\(self)m" }
        let hours = self / 60
        let minutes = self % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
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
    var plannedDate: Date? = nil
    var estimatedMinutes: Int? = nil
    var linkedNote: String?
    var recognizedTokens: [CommandToken] = []
}

struct CommandToken: Equatable, Identifiable {
    enum Kind: String {
        case date
        case time
        case course
        case estimate
    }

    let kind: Kind
    let text: String

    var id: String { "\(kind.rawValue):\(text)" }

    var icon: String {
        switch kind {
        case .date: "calendar"
        case .time: "clock"
        case .course: "tag"
        case .estimate: "hourglass"
        }
    }
}

struct SlashCommandDefinition: Identifiable {
    let command: String
    let usage: String
    let detail: String
    let icon: String
    let takesArgument: Bool

    var id: String { command }
    var insertionText: String { takesArgument ? command + " " : command }

    static let all: [SlashCommandDefinition] = [
        .init(command: "/task", usage: "/task <title> [date] [time] [duration]", detail: "Create a task", icon: "checkmark.square", takesArgument: true),
        .init(command: "/schedule", usage: "/schedule <task> at <time>", detail: "Plan an existing task", icon: "calendar.badge.plus", takesArgument: true),
        .init(command: "/capture", usage: "/capture <thought>", detail: "Save to Scratchpad", icon: "square.and.pencil", takesArgument: true),
        .init(command: "/project", usage: "/project <title> [deadline]", detail: "Create a project", icon: "folder.badge.plus", takesArgument: true),
        .init(command: "/note", usage: "/note <title>", detail: "Create a Markdown note", icon: "doc.badge.plus", takesArgument: true),
        .init(command: "/today", usage: "/today", detail: "Open today", icon: "sun.max", takesArgument: false),
        .init(command: "/inbox", usage: "/inbox", detail: "Open the inbox", icon: "tray", takesArgument: false),
        .init(command: "/tasks", usage: "/tasks", detail: "Open all tasks", icon: "checklist", takesArgument: false),
        .init(command: "/calendar", usage: "/calendar", detail: "Open the calendar", icon: "calendar", takesArgument: false),
        .init(command: "/projects", usage: "/projects", detail: "Open projects", icon: "folder", takesArgument: false),
        .init(command: "/notes", usage: "/notes", detail: "Open notes", icon: "doc.text", takesArgument: false),
        .init(command: "/files", usage: "/files", detail: "Open files and PDFs", icon: "doc.on.doc", takesArgument: false),
        .init(command: "/journal", usage: "/journal", detail: "Open the journal", icon: "book.closed", takesArgument: false),
        .init(command: "/meetings", usage: "/meetings", detail: "Open meetings", icon: "person.2", takesArgument: false),
        .init(command: "/reminders", usage: "/reminders", detail: "Open reminders", icon: "bell", takesArgument: false),
        .init(command: "/pomo", usage: "/pomo", detail: "Start a 25-minute focus session", icon: "timer", takesArgument: false),
        .init(command: "/timer", usage: "/timer", detail: "Start a stopwatch", icon: "stopwatch", takesArgument: false),
        .init(command: "/export", usage: "/export", detail: "Open export tools", icon: "square.and.arrow.up", takesArgument: false)
    ]

    static func matching(_ input: String) -> [SlashCommandDefinition] {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.hasPrefix("/") else { return [] }
        guard query != "/" else { return all }
        let words = String(query.dropFirst())
        return all.filter {
            $0.command.hasPrefix(query) ||
            query.hasPrefix($0.command + " ") ||
            $0.detail.lowercased().contains(words)
        }
    }

    static func hasEnteredArgument(in input: String) -> Bool {
        let lowered = input.lowercased()
        return all.contains { $0.takesArgument && lowered.hasPrefix($0.command + " ") }
    }
}

enum CommandIntent: Equatable {
    case createTask
    case scheduleTask
    case scheduleExistingTask(query: String)
    case capture(text: String)
    case createProject
    case createNote
    case rescheduleTask(query: String)
    case search(query: String)
    case startTimer(FocusTimerCommand)
}

enum FocusTimerCommand: Equatable {
    case countdown(seconds: Int)
    case stopwatch
}

struct CommandInterpretation: Equatable {
    let intent: CommandIntent
    let draft: QuickCommandDraft

    var plannedDate: Date { draft.plannedDate ?? draft.dueDate }

    var summary: String {
        switch intent {
        case .createTask: "Create a new task"
        case .scheduleTask: "Schedule a task"
        case .scheduleExistingTask(let query): query.isEmpty ? "Choose a task to schedule" : "Schedule “\(query)”"
        case .capture: "Save to the scratchpad"
        case .createProject: "Create a new project"
        case .createNote: "Create a new note"
        case .rescheduleTask(let query): "Reschedule “\(query)”"
        case .search(let query): "Search tasks for “\(query)”"
        case .startTimer(.countdown(let seconds)): "Start a \(Self.durationLabel(seconds)) countdown"
        case .startTimer(.stopwatch): "Start a stopwatch"
        }
    }

    private static func durationLabel(_ seconds: Int) -> String {
        if seconds.isMultiple(of: 3600) { return "\(seconds / 3600) hour" + (seconds == 3600 ? "" : "s") }
        if seconds.isMultiple(of: 60) { return "\(seconds / 60) minute" + (seconds == 60 ? "" : "s") }
        return "\(seconds) second" + (seconds == 1 ? "" : "s")
    }
}

private struct EscapedCommandInput {
    let protected: String
    private let escaped: [String]

    init(_ input: String, phrases: [String] = []) {
        var protected = ""
        var escaped: [String] = []
        var index = input.startIndex

        while index < input.endIndex {
            guard input[index] == "\\" else {
                protected.append(input[index])
                index = input.index(after: index)
                continue
            }

            let next = input.index(after: index)
            guard next < input.endIndex, !input[next].isWhitespace else {
                protected.append(input[index])
                index = next
                continue
            }

            let end = phrases
                .sorted { $0.count > $1.count }
                .compactMap { phrase -> String.Index? in
                    guard !phrase.isEmpty,
                          let range = input.range(
                              of: phrase,
                              options: [.caseInsensitive, .anchored],
                              range: next..<input.endIndex
                          ),
                          range.upperBound == input.endIndex || !(input[range.upperBound].isLetter || input[range.upperBound].isNumber) else {
                        return nil
                    }
                    return range.upperBound
                }
                .first ?? input[next...].firstIndex(where: \.isWhitespace) ?? input.endIndex
            escaped.append(String(input[next..<end]))
            protected += Self.marker(for: escaped.count - 1)
            index = end
        }

        self.protected = protected
        self.escaped = escaped
    }

    func restore(_ input: String) -> String {
        escaped.enumerated().reduce(input) { result, entry in
            result.replacingOccurrences(of: Self.marker(for: entry.offset), with: entry.element)
        }
    }

    func restoreEscapes(_ input: String) -> String {
        escaped.enumerated().reduce(input) { result, entry in
            result.replacingOccurrences(of: Self.marker(for: entry.offset), with: "\\" + entry.element)
        }
    }

    private static func marker(for index: Int) -> String {
        "\u{E000}\(index)\u{E001}"
    }
}

enum CommandInterpreter {
    static func interpret(_ input: String, now: Date = Date(), calendar: Calendar = .current, spaces: [Course] = Course.allCases) -> CommandInterpretation {
        let source = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let escaped = EscapedCommandInput(source, phrases: spaces.map(\.title))
        let trimmed = escaped.protected.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let draft = CommandParser.parse(source, now: now, calendar: calendar, spaces: spaces)

        if let timerCommand = timerCommand(in: lowered) {
            return CommandInterpretation(intent: .startTimer(timerCommand), draft: draft)
        }
        if let capture = payload(in: trimmed, prefixes: ["/capture", "capture:", "save to scratchpad"]) {
            return CommandInterpretation(intent: .capture(text: escaped.restore(capture)), draft: draft)
        }
        if payload(in: trimmed, prefixes: ["/project", "create project", "new project"]) != nil {
            return CommandInterpretation(intent: .createProject, draft: draft)
        }
        if payload(in: trimmed, prefixes: ["/note", "create note", "new note"]) != nil {
            return CommandInterpretation(intent: .createNote, draft: draft)
        }
        if let clause = inlineScheduleClause(in: trimmed) {
            var taskDraft = CommandParser.parse(escaped.restoreEscapes(clause.task), now: now, calendar: calendar, spaces: spaces)
            let planningDraft = CommandParser.parse(escaped.restoreEscapes(clause.plan), now: now, calendar: calendar, spaces: spaces)
            if !taskDraft.recognizedTokens.contains(where: { $0.kind == .date || $0.kind == .time }) {
                taskDraft.dueDate = planningDraft.dueDate
            }
            taskDraft.plannedDate = planningDraft.dueDate
            taskDraft.estimatedMinutes = taskDraft.estimatedMinutes ?? planningDraft.estimatedMinutes
            for token in planningDraft.recognizedTokens
                where token.kind == .date || token.kind == .time || token.kind == .estimate {
                if !taskDraft.recognizedTokens.contains(token) {
                    taskDraft.recognizedTokens.append(token)
                }
            }
            return CommandInterpretation(intent: .scheduleTask, draft: taskDraft)
        }
        if let clause = leadingScheduleDueClause(in: trimmed) {
            var taskDraft = CommandParser.parse(escaped.restoreEscapes(clause.plan), now: now, calendar: calendar, spaces: spaces)
            let dueDraft = CommandParser.parse(escaped.restoreEscapes(clause.due), now: now, calendar: calendar, spaces: spaces)
            taskDraft.plannedDate = taskDraft.dueDate
            taskDraft.dueDate = dueDraft.dueDate
            for token in dueDraft.recognizedTokens where token.kind == .date || token.kind == .time {
                if !taskDraft.recognizedTokens.contains(token) {
                    taskDraft.recognizedTokens.append(token)
                }
            }
            return CommandInterpretation(intent: .scheduleTask, draft: taskDraft)
        }
        if let existingTask = payload(in: trimmed, prefixes: ["/schedule"]) {
            let query = existingTask.isEmpty || draft.title == "Untitled task" ? "" : draft.title
            return CommandInterpretation(intent: .scheduleExistingTask(query: query), draft: draft)
        }
        if payload(in: trimmed, prefixes: ["schedule", "schedule:"]) != nil {
            return CommandInterpretation(intent: .scheduleTask, draft: draft)
        }
        if let target = rescheduleTarget(in: trimmed) {
            return CommandInterpretation(intent: .rescheduleTask(query: escaped.restore(target)), draft: draft)
        }
        if lowered.hasPrefix("find ") || lowered.hasPrefix("search ") {
            let query = String(trimmed.dropFirst(lowered.hasPrefix("find ") ? 5 : 7))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return CommandInterpretation(intent: .search(query: escaped.restore(query)), draft: draft)
        }
        return CommandInterpretation(intent: .createTask, draft: draft)
    }

    private static func inlineScheduleClause(in input: String) -> (task: String, plan: String)? {
        guard let marker = input.range(
            of: #"\s+\bschedule\b\s*"#,
            options: [.regularExpression, .caseInsensitive]
        ) else { return nil }
        let task = input[..<marker.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        var plan = input[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        plan = plan.replacingOccurrences(
            of: #"(?i)^(?:(?:it\s+)?(?:for|at|on)\s+|it\s+)"#,
            with: "",
            options: .regularExpression
        )
        guard !task.isEmpty, !plan.isEmpty else { return nil }
        return (task, plan)
    }

    private static func leadingScheduleDueClause(in input: String) -> (plan: String, due: String)? {
        let lowered = input.lowercased()
        guard lowered.hasPrefix("schedule ") || lowered.hasPrefix("schedule:") else { return nil }
        let body = input.replacingOccurrences(
            of: #"(?i)^schedule(?::|\s+)\s*"#,
            with: "",
            options: .regularExpression
        )
        guard let marker = body.range(
            of: #"\s+\b(?:due|by)\b\s*"#,
            options: [.regularExpression, .caseInsensitive, .backwards]
        ) else { return nil }
        let plan = body[..<marker.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let due = body[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plan.isEmpty, !due.isEmpty else { return nil }
        return (plan, due)
    }

    private static func timerCommand(in input: String) -> FocusTimerCommand? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["start pomo", "start pomodoro", "/pomo", "/pomodoro"].contains(normalized) {
            return .countdown(seconds: 25 * 60)
        }
        if ["start timer", "start stopwatch", "/timer", "/stopwatch"].contains(normalized) {
            return .stopwatch
        }

        let patterns = [
            #"^start\s+(\d+)\s*(second|seconds|minute|minutes|hour|hours)\s+(?:countdown|timer)$"#,
            #"^start\s+(?:a\s+)?(?:countdown|timer)\s+(?:for\s+)?(\d+)\s*(second|seconds|minute|minutes|hour|hours)$"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
                  let valueRange = Range(match.range(at: 1), in: normalized),
                  let unitRange = Range(match.range(at: 2), in: normalized),
                  let value = Int(normalized[valueRange]), value > 0 else { continue }
            let unit = normalized[unitRange]
            let multiplier = unit.hasPrefix("hour") ? 3600 : (unit.hasPrefix("minute") ? 60 : 1)
            return .countdown(seconds: min(value * multiplier, 24 * 60 * 60))
        }
        return nil
    }

    private static func payload(in input: String, prefixes: [String]) -> String? {
        let lowered = input.lowercased()
        guard let prefix = prefixes.first(where: { lowered == $0 || lowered.hasPrefix($0 + " ") }) else { return nil }
        return String(input.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
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
    static func parse(_ source: String, now: Date = Date(), calendar: Calendar = .current, spaces: [Course] = Course.allCases) -> QuickCommandDraft {
        let escaped = EscapedCommandInput(source, phrases: spaces.map(\.title))
        let input = escaped.protected
        let lowered = input.lowercased()
        let fallback = spaces.first(where: { $0.id == Course.general.id }) ?? spaces.first ?? .general
        let resolvedCourse = resolveCourse(in: input, spaces: spaces)
        let course = resolvedCourse?.course ?? fallback

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

        let parsedEstimate = workloadEstimate(in: input)
        if let parsedEstimate {
            recognizedTokens.append(CommandToken(kind: .estimate, text: parsedEstimate.label))
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
        title = title.replacingOccurrences(
            of: #"(?i)^\s*(?:/(?:capture|project|note|schedule|task)|create\s+(?:project|note)|new\s+(?:project|note)|save\s+to\s+scratchpad|capture:|schedule:)\s*"#,
            with: "",
            options: .regularExpression
        )
        title = title.replacingOccurrences(of: #"(?i)^\s*(?:add|create|task|move|reschedule|schedule)\s+"#, with: "", options: .regularExpression)
        if firstMatch(#"(?i)^\s*(?:/schedule|schedule(?::|\s|$))"#, in: input) != nil {
            while title.range(of: #"(?i)^\s*(?:for|at|on)\s+"#, options: .regularExpression) != nil {
                title = title.replacingOccurrences(of: #"(?i)^\s*(?:for|at|on)\s+"#, with: "", options: .regularExpression)
            }
        }
        title = title.replacingOccurrences(of: #"\s+#\w+"#, with: "", options: .regularExpression)
        let keepSubjectInTitle = firstMatch(
            #"(?i)^\s*(?:/(?:project|note)|create\s+(?:project|note)|new\s+(?:project|note))\b"#,
            in: input
        ) != nil
        if let resolvedCourse, !keepSubjectInTitle {
            for term in resolvedCourse.matchedTexts.sorted(by: { $0.count > $1.count }) {
                title = stripCourseTerm(term, from: title)
            }
        }
        title = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingConnector = #"(?i)(?:\s+|^)(?:due|by|on|at|for|to|in)\s*$"#
        while title.range(of: trailingConnector, options: .regularExpression) != nil {
            title = title.replacingOccurrences(of: trailingConnector, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        title = escaped.restore(title)
        if let first = title.first {
            title.replaceSubrange(title.startIndex...title.startIndex, with: String(first).uppercased())
        }

        return QuickCommandDraft(
            title: title.isEmpty ? "Untitled task" : title,
            course: course,
            dueDate: dueDate,
            estimatedMinutes: parsedEstimate?.minutes,
            linkedNote: course.id == Course.chemistry.id ? "Lab Notes.md" : nil,
            recognizedTokens: recognizedTokens
        )
    }

    private static func workloadEstimate(in input: String) -> (minutes: Int, label: String)? {
        guard let match = firstMatch(
            #"(?i)\b(?:(\d+)\s*h(?:\s*(\d+)\s*m)?|(\d+)\s*m)\b"#,
            in: input
        ) else { return nil }

        let minutes: Int
        if let hours = Int(match.groups[0]) {
            let remainder = Int(match.groups[1]) ?? 0
            guard remainder < 60 else { return nil }
            minutes = hours * 60 + remainder
        } else {
            minutes = Int(match.groups[2]) ?? 0
        }
        return minutes > 0 ? (minutes, match.full) : nil
    }

    private static let subjectAliases: [String: [String]] = [
        "chemistry": ["chem", "chemistry", "化学", "chems"],
        "calculus": ["calc", "calculus", "cal", "math", "数学"],
        "debate": ["debate", "deb", "辩论"],
        "history": ["hist", "history", "历史"],
        "biology": ["bio", "biology", "生物"],
        "physics": ["phys", "physics", "phy", "物理"],
        "english": ["eng", "english", "ela", "英语"],
        "literature": ["lit", "literature", "文学"],
        "spanish": ["span", "spanish", "西班牙语"],
        "french": ["fren", "french", "法语"],
        "computer science": ["cs", "comp sci", "compsci", "coding", "programming"],
        "statistics": ["stats", "stat", "statistics", "统计"],
        "geometry": ["geo", "geometry", "几何"],
        "algebra": ["alg", "algebra", "代数"],
        "economics": ["econ", "economics", "经济"],
        "government": ["gov", "govt", "government", "政治"],
        "psychology": ["psych", "psychology", "心理"]
    ]

    private static let subjectNoiseWords: Set<String> = [
        "honors", "honour", "honours", "ap", "ib", "pre", "preap", "advanced",
        "intro", "introduction", "general", "basic", "elementary", "intermediate",
        "college", "prep", "preparatory", "academic", "standard", "regular",
        "level", "class", "course", "period"
    ]

    private static func resolveCourse(in input: String, spaces: [Course]) -> (course: Course, matchedTexts: [String])? {
        var candidates: [(course: Course, matchedTexts: [String], score: Int)] = []
        for space in spaces where space.id != Course.general.id {
            let matched = courseMatchTexts(in: input, for: space)
            guard !matched.isEmpty else { continue }
            candidates.append((space, matched, courseMatchScore(space, matchedTexts: matched)))
        }
        return candidates
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.course.title.count > $1.course.title.count
            }
            .first
            .map { ($0.course, $0.matchedTexts) }
    }

    private static func courseMatchTexts(in input: String, for space: Course) -> [String] {
        var matched: [String] = []
        let lowered = input.lowercased()
        let title = space.title
        let loweredTitle = title.lowercased()

        if let hash = firstMatch(#"(?i)#\#(NSRegularExpression.escapedPattern(for: space.id))\b"#, in: input) {
            matched.append(hash.full)
        }
        if let hashTitle = firstMatch(#"(?i)#\#(NSRegularExpression.escapedPattern(for: loweredTitle.replacingOccurrences(of: " ", with: "")))\b"#, in: input) {
            matched.append(hashTitle.full)
        }
        if let titleMatch = wordMatch(of: title, in: input) {
            matched.append(titleMatch)
        }

        let significant = significantSubjectTokens(in: title)
        for token in significant where token.count >= 3 {
            if let hit = wordMatch(of: token, in: input) {
                matched.append(hit)
            }
        }

        for (canonical, aliases) in subjectAliases {
            guard subjectFamilyMatches(canonical, spaceTitle: loweredTitle, significant: significant) else { continue }
            for alias in aliases {
                if let hit = wordMatch(of: alias, in: input) {
                    matched.append(hit)
                }
            }
        }

        if lowered.contains(space.id.lowercased()), space.id.count >= 3,
           let hit = wordMatch(of: space.id, in: input) {
            matched.append(hit)
        }

        return uniquePreservingOrder(matched)
    }

    private static func courseMatchScore(_ space: Course, matchedTexts: [String]) -> Int {
        let longest = matchedTexts.map(\.count).max() ?? 0
        let exactTitle = matchedTexts.contains { $0.compare(space.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        return (exactTitle ? 100 : 0) + longest * 2 + space.title.count
    }

    private static func subjectFamilyMatches(_ canonical: String, spaceTitle: String, significant: [String]) -> Bool {
        if spaceTitle.contains(canonical) { return true }
        if significant.contains(where: { $0 == canonical || canonical.contains($0) || $0.contains(canonical) }) { return true }
        let compactTitle = spaceTitle.replacingOccurrences(of: " ", with: "")
        return compactTitle.contains(canonical.replacingOccurrences(of: " ", with: ""))
    }

    private static func significantSubjectTokens(in title: String) -> [String] {
        title
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty && !subjectNoiseWords.contains($0) && $0.count >= 3 }
    }

    private static func wordMatch(of term: String, in input: String) -> String? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: trimmed)
        if trimmed.contains(where: { $0.isWhitespace }) {
            return firstMatch("(?i)" + escaped, in: input)?.full
        }
        if trimmed.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }) {
            return firstMatch(#"(?i)(?<![A-Za-z0-9])\#(escaped)(?![A-Za-z0-9])"#, in: input)?.full
        }
        return firstMatch("(?i)" + escaped, in: input)?.full
    }

    private static func stripCourseTerm(_ term: String, from title: String) -> String {
        let trimmed = term.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "#")))
        guard !trimmed.isEmpty else { return title }
        let escaped = NSRegularExpression.escapedPattern(for: trimmed)
        let replacement = trimmed.unicodeScalars.contains(where: { $0.isASCII }) ? " " : ""
        if trimmed.contains(where: { $0.isWhitespace }) {
            return title.replacingOccurrences(of: "(?i)" + escaped, with: replacement, options: .regularExpression)
        }
        if trimmed.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }) {
            return title.replacingOccurrences(
                of: #"(?i)(?<![A-Za-z0-9])\#(escaped)(?![A-Za-z0-9])"#,
                with: replacement,
                options: .regularExpression
            )
        }
        return title.replacingOccurrences(of: "(?i)" + escaped, with: replacement, options: .regularExpression)
    }

    private static func uniquePreservingOrder(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter {
            let key = $0.lowercased()
            return seen.insert(key).inserted
        }
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
        if let tomorrow = firstMatch(#"(?i)\btomor+ow\b"#, in: input) {
            return (calendar.date(byAdding: .day, value: 1, to: now) ?? now, tomorrow.full)
        }
        if input.contains("明天") {
            let label = "明天"
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

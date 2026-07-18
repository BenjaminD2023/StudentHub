import Foundation

enum HubSection: String, CaseIterable, Codable, Identifiable {
    case today
    case inbox
    case calendar
    case tasks
    case projects
    case notes
    case files
    case journal
    case meetings
    case reminders
    case pomodoro
    case export
    case spaceHome

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .inbox: "Inbox"
        case .calendar: "Calendar"
        case .tasks: "All Tasks"
        case .projects: "Projects"
        case .notes: "Notes"
        case .files: "Files & PDFs"
        case .journal: "Journal"
        case .meetings: "Meetings"
        case .reminders: "Reminders"
        case .pomodoro: "Pomodoro"
        case .export: "Export"
        case .spaceHome: "Space"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .inbox: "tray"
        case .calendar: "calendar.day.timeline.left"
        case .tasks: "checklist"
        case .projects: "folder"
        case .notes: "doc.text"
        case .files: "doc.on.doc"
        case .journal: "book.closed"
        case .meetings: "person.2"
        case .reminders: "bell"
        case .pomodoro: "timer"
        case .export: "square.and.arrow.up"
        case .spaceHome: "rectangle.3.group.fill"
        }
    }
}

struct HubProject: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var course: Course
    var deadline: Date
    var details: String
    var isArchived: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        course: Course,
        deadline: Date,
        details: String = "",
        isArchived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.course = course
        self.deadline = deadline
        self.details = details
        self.isArchived = isArchived
        self.createdAt = createdAt
    }
}

struct HubNote: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var folder: String
    var markdown: String
    var course: Course
    var linkedTaskIDs: [UUID]
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        folder: String = "Inbox",
        markdown: String = "",
        course: Course = .general,
        linkedTaskIDs: [UUID] = [],
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.folder = folder
        self.markdown = markdown
        self.course = course
        self.linkedTaskIDs = linkedTaskIDs
        self.modifiedAt = modifiedAt
    }
}

struct JournalEntry: Identifiable, Hashable, Codable {
    let id: UUID
    var date: Date
    var title: String
    var body: String
    var mood: Int
    var isDateLinked: Bool

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String,
        body: String = "",
        mood: Int = 3,
        isDateLinked: Bool = true
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.body = body
        self.mood = mood
        self.isDateLinked = isDateLinked
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, title, body, mood, isDateLinked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        mood = try container.decode(Int.self, forKey: .mood)
        isDateLinked = try container.decodeIfPresent(Bool.self, forKey: .isDateLinked) ?? true
    }
}

struct MeetingRecord: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var date: Date
    var projectID: UUID?
    var transcript: String
    var summary: String
    var actionTaskIDs: [UUID]

    init(
        id: UUID = UUID(),
        title: String,
        date: Date = Date(),
        projectID: UUID? = nil,
        transcript: String = "",
        summary: String = "",
        actionTaskIDs: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.projectID = projectID
        self.transcript = transcript
        self.summary = summary
        self.actionTaskIDs = actionTaskIDs
    }
}

struct HubReminder: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var dueDate: Date
    var isCompleted: Bool
    var linkedTaskID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date,
        isCompleted: Bool = false,
        linkedTaskID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.linkedTaskID = linkedTaskID
    }
}

struct HubFileItem: Identifiable, Hashable, Codable {
    enum Kind: String, Codable {
        case pdf
        case image
        case document
        case other
    }

    let id: UUID
    var displayName: String
    var storedFileName: String
    var kind: Kind
    var course: Course
    var annotationNotes: String
    var addedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        storedFileName: String,
        kind: Kind,
        course: Course = .general,
        annotationNotes: String = "",
        addedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.storedFileName = storedFileName
        self.kind = kind
        self.course = course
        self.annotationNotes = annotationNotes
        self.addedAt = addedAt
    }
}

struct WhiteboardCapture: Identifiable, Hashable, Codable {
    let id: UUID
    var text: String
    var createdAt: Date
    var linkedTaskID: UUID?
    var linkedNoteID: UUID?

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        linkedTaskID: UUID? = nil,
        linkedNoteID: UUID? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.linkedTaskID = linkedTaskID
        self.linkedNoteID = linkedNoteID
    }
}

enum FocusTimerMode: String, Codable {
    case countdown
    case stopwatch
}

struct FocusTimerSnapshot: Codable, Equatable {
    var mode: FocusTimerMode
    var isRunning: Bool
    var countdownRemaining: Int
    var countdownEndDate: Date?
    var stopwatchElapsed: Int
    var stopwatchStartedAt: Date?

    static let idlePomodoro = FocusTimerSnapshot(
        mode: .countdown,
        isRunning: false,
        countdownRemaining: 25 * 60,
        countdownEndDate: nil,
        stopwatchElapsed: 0,
        stopwatchStartedAt: nil
    )
}

struct WorkspaceSnapshot: Codable {
    var modifiedAt: Date
    var spaces: [Course]
    var tasks: [HubTask]
    var scheduleBlocks: [ScheduleBlock]
    var projects: [HubProject]
    var notes: [HubNote]
    var journalEntries: [JournalEntry]
    var meetings: [MeetingRecord]
    var reminders: [HubReminder]
    var files: [HubFileItem]
    var captures: [WhiteboardCapture]
    var focusTimer: FocusTimerSnapshot?

    init(
        modifiedAt: Date = Date(),
        spaces: [Course] = Course.allCases,
        tasks: [HubTask],
        scheduleBlocks: [ScheduleBlock],
        projects: [HubProject],
        notes: [HubNote],
        journalEntries: [JournalEntry],
        meetings: [MeetingRecord],
        reminders: [HubReminder],
        files: [HubFileItem],
        captures: [WhiteboardCapture],
        focusTimer: FocusTimerSnapshot? = nil
    ) {
        self.modifiedAt = modifiedAt
        self.spaces = spaces
        self.tasks = tasks
        self.scheduleBlocks = scheduleBlocks
        self.projects = projects
        self.notes = notes
        self.journalEntries = journalEntries
        self.meetings = meetings
        self.reminders = reminders
        self.files = files
        self.captures = captures
        self.focusTimer = focusTimer
    }

    private enum CodingKeys: String, CodingKey {
        case modifiedAt
        case spaces
        case tasks
        case scheduleBlocks
        case projects
        case notes
        case journalEntries
        case meetings
        case reminders
        case files
        case captures
        case focusTimer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
        spaces = try container.decodeIfPresent([Course].self, forKey: .spaces) ?? Course.allCases
        tasks = try container.decode([HubTask].self, forKey: .tasks)
        scheduleBlocks = try container.decode([ScheduleBlock].self, forKey: .scheduleBlocks)
        projects = try container.decode([HubProject].self, forKey: .projects)
        notes = try container.decode([HubNote].self, forKey: .notes)
        journalEntries = try container.decode([JournalEntry].self, forKey: .journalEntries)
        meetings = try container.decode([MeetingRecord].self, forKey: .meetings)
        reminders = try container.decode([HubReminder].self, forKey: .reminders)
        files = try container.decode([HubFileItem].self, forKey: .files)
        captures = try container.decode([WhiteboardCapture].self, forKey: .captures)
        focusTimer = try container.decodeIfPresent(FocusTimerSnapshot.self, forKey: .focusTimer)
    }
}

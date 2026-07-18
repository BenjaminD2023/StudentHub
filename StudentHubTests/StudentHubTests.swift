import XCTest
@testable import StudentHub

final class StudentHubTests: XCTestCase {
    func testUnsignedLocalBuildDoesNotCreateCloudContainer() {
        XCTAssertFalse(CloudSyncAvailability.isConfigured)
    }

    func testQuickCommandParsesCourseDateTimeAndCleanTitle() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 17,
            hour: 9
        )))

        let draft = CommandParser.parse(
            "Finish lab report tomorrow 8:15 pm #chem",
            now: now,
            calendar: calendar
        )
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.dueDate)

        XCTAssertEqual(draft.title, "Finish lab report")
        XCTAssertEqual(draft.course, .chemistry)
        XCTAssertEqual(components.day, 18)
        XCTAssertEqual(components.hour, 20)
        XCTAssertEqual(components.minute, 15)
        XCTAssertEqual(draft.linkedNote, "Lab Notes.md")
    }

    func testQuickCommandRecognizesWeekdayAnd24HourTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 9)))

        let draft = CommandParser.parse("History outline next Friday 16:30", now: now, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: draft.dueDate)

        XCTAssertEqual(draft.title, "History outline")
        XCTAssertEqual(components.day, 24)
        XCTAssertEqual(components.hour, 16)
        XCTAssertEqual(components.minute, 30)
        XCTAssertTrue(draft.recognizedTokens.contains { $0.kind == .date })
        XCTAssertTrue(draft.recognizedTokens.contains { $0.kind == .time })
    }

    func testQuickCommandRecognizesChineseRelativeDateAndTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 9)))

        let draft = CommandParser.parse("交化学作业 明天下午4点", now: now, calendar: calendar)
        let components = calendar.dateComponents([.day, .hour, .minute], from: draft.dueDate)

        XCTAssertEqual(draft.title, "交化学作业")
        XCTAssertEqual(components.day, 18)
        XCTAssertEqual(components.hour, 16)
        XCTAssertEqual(components.minute, 0)
    }

    func testCommandInterpreterFindsRescheduleTarget() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 9)))

        let result = CommandInterpreter.interpret("move Court case prep to Friday 4 pm", now: now, calendar: calendar)

        XCTAssertEqual(result.intent, .rescheduleTask(query: "Court case prep"))
        XCTAssertEqual(calendar.component(.hour, from: result.draft.dueDate), 16)
    }

    func testCommandInterpreterRecognizesCaptureProjectAndNoteCommands() {
        let capture = CommandInterpreter.interpret("/capture Ask Ms. Li about sources")
        let project = CommandInterpreter.interpret("/project History presentation next Friday")
        let note = CommandInterpreter.interpret("/note Debate evidence")

        XCTAssertEqual(capture.intent, .capture(text: "Ask Ms. Li about sources"))
        XCTAssertEqual(capture.draft.title, "Ask Ms. Li about sources")
        XCTAssertEqual(project.intent, .createProject)
        XCTAssertEqual(project.draft.title, "History presentation")
        XCTAssertEqual(note.intent, .createNote)
        XCTAssertEqual(note.draft.title, "Debate evidence")
    }

    func testCommandInterpreterRecognizesFocusTimerCommands() {
        XCTAssertEqual(
            CommandInterpreter.interpret("start pomo").intent,
            .startTimer(.countdown(seconds: 25 * 60))
        )
        XCTAssertEqual(
            CommandInterpreter.interpret("start 25 minute countdown").intent,
            .startTimer(.countdown(seconds: 25 * 60))
        )
        XCTAssertEqual(
            CommandInterpreter.interpret("start 90 second countdown").intent,
            .startTimer(.countdown(seconds: 90))
        )
        XCTAssertEqual(
            CommandInterpreter.interpret("start timer").intent,
            .startTimer(.stopwatch)
        )
    }

    @MainActor
    func testProjectCreationTrimsInputAndSelectsCreatedProject() throws {
        let state = AppState(seedData: false, persistenceEnabled: false)
        let writing = try XCTUnwrap(state.addSpace(title: "Writing", colorHex: 0xA978F2))

        let project = state.addProject(title: "  Research portfolio  ", course: writing, deadline: Date(), details: "  Sources  ")

        XCTAssertEqual(project.title, "Research portfolio")
        XCTAssertEqual(project.details, "Sources")
        XCTAssertEqual(project.course, writing)
        XCTAssertEqual(state.projects.first?.id, project.id)
        XCTAssertEqual(state.selectedProjectID, project.id)
    }

    func testQuickCommandRecognizesNamedMonthAndRelativeOffset() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 9)))

        let named = CommandParser.parse("Submit essay due July 22nd at 4 pm", now: now, calendar: calendar)
        let namedParts = calendar.dateComponents([.year, .month, .day, .hour], from: named.dueDate)
        XCTAssertEqual(named.title, "Submit essay")
        XCTAssertEqual(namedParts.year, 2026)
        XCTAssertEqual(namedParts.month, 7)
        XCTAssertEqual(namedParts.day, 22)
        XCTAssertEqual(namedParts.hour, 16)

        let relative = CommandParser.parse("Finish slides in 3 days at 6 pm", now: now, calendar: calendar)
        let relativeParts = calendar.dateComponents([.day, .hour], from: relative.dueDate)
        XCTAssertEqual(relative.title, "Finish slides")
        XCTAssertEqual(relativeParts.day, 20)
        XCTAssertEqual(relativeParts.hour, 18)
    }

    func testQuickCommandRecognizesChineseCalendarDatesAndWeekdays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 9)))

        let calendarDate = CommandParser.parse("交历史作业 7月20日 20:00", now: now, calendar: calendar)
        let calendarParts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: calendarDate.dueDate)
        XCTAssertEqual(calendarDate.title, "交历史作业")
        XCTAssertEqual(calendarParts.year, 2026)
        XCTAssertEqual(calendarParts.month, 7)
        XCTAssertEqual(calendarParts.day, 20)
        XCTAssertEqual(calendarParts.hour, 20)
        XCTAssertEqual(calendarParts.minute, 0)

        let weekday = CommandParser.parse("准备演讲 下周三下午4点", now: now, calendar: calendar)
        let weekdayParts = calendar.dateComponents([.month, .day, .hour], from: weekday.dueDate)
        XCTAssertEqual(weekday.title, "准备演讲")
        XCTAssertEqual(weekdayParts.month, 7)
        XCTAssertEqual(weekdayParts.day, 22)
        XCTAssertEqual(weekdayParts.hour, 16)
    }

    func testQuickCommandUsesCustomSpace() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 9)))
        let literature = Course(id: "literature", title: "Literature", colorHex: 0xA978F2)

        let draft = CommandParser.parse(
            "Finish close reading tomorrow #literature",
            now: now,
            calendar: calendar,
            spaces: [literature, .general]
        )

        XCTAssertEqual(draft.title, "Finish close reading")
        XCTAssertEqual(draft.course, literature)
        XCTAssertTrue(draft.recognizedTokens.contains { $0.kind == .course })
    }

    func testLegacyCourseValueStillDecodes() throws {
        let decoded = try JSONDecoder().decode(Course.self, from: Data("\"chemistry\"".utf8))

        XCTAssertEqual(decoded, .chemistry)
        XCTAssertEqual(decoded.title, "Chemistry")
        XCTAssertEqual(decoded.colorHex, Course.chemistry.colorHex)
    }

    @MainActor
    func testDeletingSpaceReassignsItsContent() throws {
        let state = AppState(seedData: false, persistenceEnabled: false)
        let writing = try XCTUnwrap(state.addSpace(title: "Writing", colorHex: 0xA978F2))
        let task = state.addTask(title: "Draft essay", course: writing)
        let project = state.addProject(title: "Portfolio", course: writing, deadline: Date())

        state.deleteSpace(writing.id, reassignTo: Course.general.id)

        XCTAssertFalse(state.spaces.contains(where: { $0.id == writing.id }))
        XCTAssertEqual(state.tasks.first(where: { $0.id == task.id })?.course, .general)
        XCTAssertEqual(state.projects.first(where: { $0.id == project.id })?.course, .general)
    }

    @MainActor
    func testDirectSpaceDeletionRemovesAssignedContent() throws {
        let state = AppState(seedData: false, persistenceEnabled: false)
        let writing = try XCTUnwrap(state.addSpace(title: "Writing", colorHex: 0xA978F2))
        let deletedTask = state.addTask(title: "Draft essay", course: writing)
        let deletedProject = state.addProject(title: "Portfolio", course: writing, deadline: Date())
        let retainedTask = state.addTask(title: "Read chapter", course: .general, projectID: deletedProject.id)
        state.addScheduleBlock(title: "Draft essay", course: writing, date: Date(), startHour: 16, duration: 1)

        state.deleteSpaceAndContents(writing.id)

        XCTAssertFalse(state.spaces.contains(where: { $0.id == writing.id }))
        XCTAssertFalse(state.tasks.contains(where: { $0.id == deletedTask.id }))
        XCTAssertFalse(state.projects.contains(where: { $0.id == deletedProject.id }))
        XCTAssertTrue(state.scheduleBlocks.isEmpty)
        XCTAssertNil(state.tasks.first(where: { $0.id == retainedTask.id })?.projectID)
    }

    func testWorkspaceSnapshotRoundTripsAllLinkedContent() throws {
        let project = HubProject(title: "History presentation", course: .general, deadline: Date(timeIntervalSince1970: 2_000))
        let note = HubNote(title: "Research", linkedTaskIDs: [], modifiedAt: Date(timeIntervalSince1970: 3_000))
        let task = HubTask(
            title: "Find sources",
            course: .general,
            dueDate: Date(timeIntervalSince1970: 4_000),
            projectID: project.id,
            linkedNoteID: note.id
        )
        let capture = WhiteboardCapture(text: "Ask teacher about citations", linkedTaskID: task.id, linkedNoteID: note.id)
        let customSpace = Course(id: "history", title: "History", colorHex: 0xA978F2)
        let snapshot = WorkspaceSnapshot(
            modifiedAt: Date(timeIntervalSince1970: 5_000),
            spaces: [customSpace, .general],
            tasks: [task],
            scheduleBlocks: [],
            projects: [project],
            notes: [note],
            journalEntries: [],
            meetings: [],
            reminders: [],
            files: [],
            captures: [capture]
        )

        let decoded = try XCTUnwrap(WorkspaceStorage.decode(try WorkspaceStorage.encode(snapshot)))

        XCTAssertEqual(decoded.modifiedAt, snapshot.modifiedAt)
        XCTAssertEqual(decoded.spaces, [customSpace, .general])
        XCTAssertEqual(decoded.tasks.first?.projectID, project.id)
        XCTAssertEqual(decoded.tasks.first?.linkedNoteID, note.id)
        XCTAssertEqual(decoded.captures.first?.linkedTaskID, task.id)
        XCTAssertEqual(decoded.captures.first?.linkedNoteID, note.id)
    }

    func testWorkspaceWithoutSyncTimestampStillLoads() throws {
        let snapshot = WorkspaceSnapshot(
            tasks: [],
            scheduleBlocks: [],
            projects: [],
            notes: [],
            journalEntries: [],
            meetings: [],
            reminders: [],
            files: [],
            captures: []
        )
        let encoded = try WorkspaceStorage.encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "modifiedAt")
        object.removeValue(forKey: "spaces")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try XCTUnwrap(WorkspaceStorage.decode(legacyData))

        XCTAssertEqual(decoded.modifiedAt, Date.distantPast)
        XCTAssertEqual(decoded.spaces, Course.allCases)
        XCTAssertTrue(decoded.tasks.isEmpty)
    }

    func testLegacyJournalEntryDefaultsToDated() throws {
        let entry = JournalEntry(title: "Legacy entry")
        let encoded = try JSONEncoder().encode(entry)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "isDateLinked")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(JournalEntry.self, from: legacyData)

        XCTAssertTrue(decoded.isDateLinked)
    }

    func testUndatedJournalMemoRoundTrips() throws {
        let memo = JournalEntry(title: "Ideas", body: "Unsorted thoughts", isDateLinked: false)

        let decoded = try JSONDecoder().decode(JournalEntry.self, from: JSONEncoder().encode(memo))

        XCTAssertFalse(decoded.isDateLinked)
        XCTAssertEqual(decoded.title, "Ideas")
        XCTAssertEqual(decoded.body, "Unsorted thoughts")
    }
}

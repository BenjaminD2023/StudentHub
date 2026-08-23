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

        XCTAssertEqual(draft.title, "交作业")
        XCTAssertEqual(draft.course, .chemistry)
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

    func testQuickCommandMatchesSubjectAbbreviationsToCurrentCourse() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 9)))
        let honorsChemistry = Course(id: "honors-chemistry", title: "Honors Chemistry", colorHex: 0xF5B824)
        let apCalculus = Course(id: "ap-calculus", title: "AP Calculus", colorHex: 0x428CFA)
        let spaces = [honorsChemistry, apCalculus, .general]

        let abbreviated = CommandParser.parse("chem lab report tomorrow 7:30 pm", now: now, calendar: calendar, spaces: spaces)
        XCTAssertEqual(abbreviated.title, "Lab report")
        XCTAssertEqual(abbreviated.course, honorsChemistry)
        XCTAssertTrue(abbreviated.recognizedTokens.contains { $0.kind == .course && $0.text == "Honors Chemistry" })

        let fullName = CommandParser.parse("Finish chemistry worksheet Friday", now: now, calendar: calendar, spaces: spaces)
        XCTAssertEqual(fullName.title, "Finish worksheet")
        XCTAssertEqual(fullName.course, honorsChemistry)

        let calc = CommandParser.parse("calc limits packet", now: now, calendar: calendar, spaces: spaces)
        XCTAssertEqual(calc.title, "Limits packet")
        XCTAssertEqual(calc.course, apCalculus)
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

    @MainActor
    func testSpacesCanBeReorderedAndNewSpaceAcceptsNotes() throws {
        let state = AppState(seedData: false, persistenceEnabled: false)
        let writing = try XCTUnwrap(state.addSpace(title: "Writing", colorHex: 0xA978F2))

        state.moveSpaces(
            fromOffsets: IndexSet(integer: state.spaces.count - 1),
            toOffset: 0
        )
        state.moveSpace(writing.id, by: 1)
        let note = state.addNote(title: "Essay plan", course: writing)

        XCTAssertEqual(state.spaces.dropFirst().first, writing)
        XCTAssertEqual(state.notes.first(where: { $0.id == note.id })?.course, writing)
    }

    func testMarkdownToolsFormatExistingSelectionAndCreateTables() {
        let source = "Review these words today"
        let selected = (source as NSString).range(of: "these words")
        let bold = MarkdownTool.bold.applying(to: source, selection: selected)
        let table = MarkdownTool.table.applying(
            to: "",
            selection: NSRange(location: 0, length: 0)
        )

        XCTAssertEqual(bold.text, "Review **these words** today")
        XCTAssertTrue(table.text.contains("| Column 1 | Column 2 |"))
    }

    func testMarkdownToolbarFormatsSelectedTextWithWordStyles() {
        let source = "Make selected words clearer"
        let selected = (source as NSString).range(of: "selected words")

        let strike = MarkdownTool.strikethrough.applyingShortcut(to: source, selection: selected)
        let underline = MarkdownTool.underline.applyingShortcut(to: source, selection: selected)
        let highlight = MarkdownTool.highlight.applyingShortcut(to: source, selection: selected)

        XCTAssertEqual(strike.text, "Make ~~selected words~~ clearer")
        XCTAssertEqual(underline.text, "Make {{underline|selected words}} clearer")
        XCTAssertEqual(highlight.text, "Make ==selected words== clearer")
        XCTAssertEqual((underline.text as NSString).substring(with: underline.selection), "selected words")
    }

    func testMarkdownChecklistCanBeToggledFromItsRenderedMarker() throws {
        let source = "Heading\n- [ ] Read chapter\nFooter"
        let markerIndex = (source as NSString).range(of: "[ ]").location + 1

        let checked = try XCTUnwrap(MarkdownChecklist.togglingMarker(in: source, characterIndex: markerIndex))
        let unchecked = try XCTUnwrap(MarkdownChecklist.togglingLine(in: checked.text, lineNumber: 1))

        XCTAssertEqual(checked.text, "Heading\n- [x] Read chapter\nFooter")
        XCTAssertEqual(unchecked.text, source)
    }

    func testMarkdownKeyboardShortcutsToggleInlineFormatting() {
        let source = "Review these words today"
        let selected = (source as NSString).range(of: "these words")
        let bold = MarkdownTool.bold.applyingShortcut(to: source, selection: selected)
        let unbold = MarkdownTool.bold.applyingShortcut(to: bold.text, selection: bold.selection)
        let insertion = MarkdownTool.italic.applyingShortcut(
            to: "Start ",
            selection: NSRange(location: 6, length: 0)
        )

        XCTAssertEqual(bold.text, "Review **these words** today")
        XCTAssertEqual((bold.text as NSString).substring(with: bold.selection), "these words")
        XCTAssertEqual(unbold.text, source)
        XCTAssertEqual(insertion.text, "Start **")
        XCTAssertEqual(insertion.selection, NSRange(location: 7, length: 0))
    }

    func testMarkdownTextColorAppliesRecolorsAndReturnsToAutomatic() {
        let source = "Review these words today"
        let selected = (source as NSString).range(of: "these words")
        let red = MarkdownTextColor(name: "Red", hex: 0xDC3545)
        let blue = MarkdownTextColor(name: "Blue", hex: 0x2563EB)
        let automatic = MarkdownTextColor(name: "Automatic", hex: nil)

        let colored = MarkdownColorFormatting.applying(red, to: source, selection: selected)
        let innerSelection = (colored.text as NSString).range(of: "these")
        let recolored = MarkdownColorFormatting.applying(blue, to: colored.text, selection: innerSelection)
        let cleared = MarkdownColorFormatting.applying(automatic, to: colored.text, selection: colored.selection)

        XCTAssertEqual((colored.text as NSString).substring(with: colored.selection), "these words")
        XCTAssertTrue(colored.text.contains("{{color:#DC3545|these words}}"))
        XCTAssertTrue(recolored.text.contains("{{color:#2563EB|these}}"))
        XCTAssertEqual(cleared.text, source)
    }

    func testNoteProducesARealOfficeOpenXMLDocument() throws {
        let note = HubNote(
            title: "Styled notes",
            markdown: "# Heading\n\nA {{color:#DC3545|**bold** idea}} with *emphasis*, {{underline|underlining}}, ==highlighting==, and ~~striking~~.",
            course: .calculus
        )

        let data = try WorkspaceStorage.officeOpenXMLData(for: note)

        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B])
        XCTAssertGreaterThan(data.count, 1_000)
        XCTAssertNotNil(data.range(of: Data("word/document.xml".utf8)))
        XCTAssertNotNil(data.range(of: Data("428CFA".utf8)))
        XCTAssertNotNil(data.range(of: Data("DC3545".utf8)))
        XCTAssertNotNil(data.range(of: Data("<w:u w:val=\"single\"/>".utf8)))
        XCTAssertNotNil(data.range(of: Data("<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"FFF2A8\"/>".utf8)))
        XCTAssertNotNil(data.range(of: Data("<w:strike/>".utf8)))
        #if os(macOS)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("docx")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-tqq", url.path]
        unzip.standardOutput = FileHandle.nullDevice
        unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        unzip.waitUntilExit()
        XCTAssertEqual(unzip.terminationStatus, 0)
        #endif
    }

    func testExportStorageListsAndDeletesOnlyExportFiles() throws {
        try WorkspaceStorage.prepareDirectories()
        let url = WorkspaceStorage.exportsURL
            .appendingPathComponent("delete-test-\(UUID().uuidString)")
            .appendingPathExtension("txt")
        try Data("temporary".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(WorkspaceStorage.exportedFiles().contains(url))
        try WorkspaceStorage.deleteExport(at: url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        XCTAssertThrowsError(try WorkspaceStorage.deleteExport(at: outside))
    }

    func testMarkdownTableExportsAsExcelCompatibleCSV() {
        let markdown = """
        | Assignment | Due |
        | --- | --- |
        | Lab report | Friday |
        """

        let csv = WorkspaceStorage.csvFromMarkdownTables(markdown)

        XCTAssertEqual(csv, "\"Assignment\",\"Due\"\n\"Lab report\",\"Friday\"\n")
    }

    @MainActor
    func testCustomPomodoroAndExactCalendarUpdate() throws {
        let state = AppState(seedData: false, persistenceEnabled: false)
        state.resetPomodoro(minutes: 42)
        state.addScheduleBlock(
            title: "Late study",
            course: .general,
            date: Date(),
            startHour: 22 + 7.0 / 60.0,
            duration: 53.0 / 60.0
        )
        var block = try XCTUnwrap(state.scheduleBlocks.first)
        block.startHour = 23 + 5.0 / 60.0
        block.duration = 40.0 / 60.0
        state.updateScheduleBlock(block)

        XCTAssertEqual(state.pomodoroRemaining, 42 * 60)
        XCTAssertEqual(state.scheduleBlocks.first?.startHour ?? 0, 23 + 5.0 / 60.0, accuracy: 0.0001)
        XCTAssertEqual(state.scheduleBlocks.first?.duration ?? 0, 40.0 / 60.0, accuracy: 0.0001)
    }

    @MainActor
    func testCreatingATaskFromQuickCommandDoesNotAlsoSaveACapture() {
        let state = AppState(seedData: false, persistenceEnabled: false)
        let draft = QuickCommandDraft(
            title: "Lab report",
            course: .chemistry,
            dueDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        state.createTask(from: draft)

        XCTAssertEqual(state.tasks.map(\.title), ["Lab report"])
        XCTAssertTrue(state.captures.isEmpty)
    }

    @MainActor
    func testUpdatingACaptureRewritesItsTextAndIgnoresBlankEdits() {
        let state = AppState(seedData: false, persistenceEnabled: false)
        let capture = state.addCapture("Ask about citations")
        let originalText = capture.text

        state.updateCapture(capture.id, text: "  Ask Ms. Li about citations  ")
        XCTAssertEqual(state.captures.first?.text, "Ask Ms. Li about citations")

        state.updateCapture(capture.id, text: "   ")
        XCTAssertEqual(state.captures.first?.text, "Ask Ms. Li about citations")

        state.updateCapture(UUID(), text: "Should not appear")
        XCTAssertEqual(state.captures.map(\.text), ["Ask Ms. Li about citations"])
        XCTAssertEqual(originalText, "Ask about citations")
    }
}

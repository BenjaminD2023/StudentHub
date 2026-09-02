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

    #if os(macOS)
    @MainActor
    func testMenuBarGroupsEveryOpenTaskOnce() throws {
        let state = AppState(seedData: false, persistenceEnabled: false)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))

        state.addTask(title: "Overdue", dueDate: yesterday)
        state.addTask(title: "Unscheduled", dueDate: tomorrow)
        let planned = state.addTask(title: "Planned", dueDate: tomorrow)
        state.schedule(planned.id, at: 19.5, on: tomorrow)
        let completed = state.addTask(title: "Completed", dueDate: tomorrow)
        state.toggleComplete(completed.id)

        XCTAssertEqual(state.menuBarTasks(in: .overdue, asOf: today).map(\.title), ["Overdue"])
        XCTAssertEqual(state.menuBarTasks(in: .unscheduled, asOf: today).map(\.title), ["Unscheduled"])
        XCTAssertEqual(state.menuBarTasks(in: .planned, asOf: today).map(\.title), ["Planned"])
        let plannedDate = try XCTUnwrap(state.menuBarPlannedDate(for: planned.id, calendar: calendar))
        XCTAssertTrue(calendar.isDate(plannedDate, inSameDayAs: tomorrow))
        XCTAssertEqual(calendar.component(.hour, from: plannedDate), 19)
        XCTAssertEqual(calendar.component(.minute, from: plannedDate), 30)
    }

    @MainActor
    func testMenuBarScheduleUsesThirtyHourWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 27)))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        let state = AppState(seedData: false, persistenceEnabled: false)

        let late = state.addTask(title: "Late", dueDate: day)
        let early = state.addTask(title: "Early", dueDate: nextDay)
        let outside = state.addTask(title: "Outside", dueDate: nextDay)
        state.schedule(late.id, at: 23.5, on: day)
        state.schedule(early.id, at: 5.5, on: nextDay)
        state.schedule(outside.id, at: 6, on: nextDay)

        let blocks = state.menuBarScheduleBlocks(on: day, calendar: calendar)
        XCTAssertEqual(blocks.map(\.title), ["Late", "Early"])
        XCTAssertEqual(
            state.menuBarScheduleStartMinute(for: try XCTUnwrap(blocks.last), on: day, calendar: calendar),
            24 * 60 + 5 * 60 + 30
        )
    }

    func testMenuBarDropSnapsToFiveMinuteSlots() {
        let rowHeight: CGFloat = 60

        XCTAssertEqual(MacMenuBarView.snappedScheduleMinute(locationY: 0, rowHeight: rowHeight), 0)
        XCTAssertEqual(MacMenuBarView.snappedScheduleMinute(locationY: 2, rowHeight: rowHeight), 0)
        XCTAssertEqual(MacMenuBarView.snappedScheduleMinute(locationY: 3, rowHeight: rowHeight), 5)
        XCTAssertEqual(MacMenuBarView.snappedScheduleMinute(locationY: 10 * rowHeight + 3, rowHeight: rowHeight), 10 * 60 + 5)
        XCTAssertEqual(MacMenuBarView.snappedScheduleMinute(locationY: 30 * rowHeight, rowHeight: rowHeight), 30 * 60 - 5)
    }

    #endif

    @MainActor
    func testPredictedTimeParsesPersistsAndDrivesScheduleDuration() throws {
        let draft = CommandParser.parse("Write essay tomorrow 1h 30m")
        XCTAssertEqual(draft.title, "Write essay")
        XCTAssertEqual(draft.estimatedMinutes, 90)

        let state = AppState(seedData: false, persistenceEnabled: false)
        state.createTask(from: draft)
        let task = try XCTUnwrap(state.tasks.first)
        XCTAssertEqual(task.estimatedMinutes, 90)

        state.schedule(task.id, at: 16, on: Date())
        XCTAssertEqual(state.scheduleBlocks.first(where: { $0.linkedTaskID == task.id })?.duration, 1.5)

        var revised = task
        revised.estimatedMinutes = 45
        state.updateTask(revised)
        XCTAssertEqual(state.scheduleBlocks.first(where: { $0.linkedTaskID == task.id })?.duration, 0.75)
    }

    func testDashboardDropSnapsToFiveMinuteSlots() {
        let rowHeight: CGFloat = 60

        XCTAssertEqual(DayTimelineView.snappedScheduleHour(for: 10 * rowHeight + 2, rowHeight: rowHeight), 10)
        XCTAssertEqual(
            DayTimelineView.snappedScheduleHour(for: 10 * rowHeight + 3, rowHeight: rowHeight),
            10 + 5.0 / 60.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            DayTimelineView.snappedScheduleHour(for: 24 * rowHeight + 5, rowHeight: rowHeight),
            24 + 5.0 / 60.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            DayTimelineView.snappedScheduleHour(for: 30 * rowHeight, rowHeight: rowHeight),
            29 + 55.0 / 60.0,
            accuracy: 0.0001
        )
    }

    func testDashboardAdvancesOnlyWhenFollowingToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let saturday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 29)))
        let sunday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: saturday))
        let monday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: sunday))

        XCTAssertEqual(
            DayTimelineView.refreshedSelection(saturday, from: saturday, to: sunday, force: false, calendar: calendar),
            sunday
        )
        XCTAssertEqual(
            DayTimelineView.refreshedSelection(monday, from: saturday, to: sunday, force: false, calendar: calendar),
            monday
        )
        XCTAssertEqual(
            DayTimelineView.refreshedSelection(monday, from: saturday, to: sunday, force: true, calendar: calendar),
            sunday
        )
    }

    func testPlannedSidebarIncludesAllOpenScheduledTasksInTimeOrder() {
        let earlier = HubTask(title: "Earlier", course: .general, dueDate: Date())
        let later = HubTask(title: "Later", course: .general, dueDate: Date())
        let completed = HubTask(title: "Done", course: .general, dueDate: Date(), isCompleted: true)
        let firstDay = Date(timeIntervalSince1970: 86_400)
        let secondDay = Date(timeIntervalSince1970: 172_800)
        let blocks = [
            ScheduleBlock(title: later.title, subtitle: "", course: .general, startHour: 9, duration: 1, date: secondDay, linkedTaskID: later.id),
            ScheduleBlock(title: completed.title, subtitle: "", course: .general, startHour: 8, duration: 1, date: firstDay, linkedTaskID: completed.id),
            ScheduleBlock(title: earlier.title, subtitle: "", course: .general, startHour: 15, duration: 1, date: firstDay, linkedTaskID: earlier.id),
            ScheduleBlock(title: "Standalone", subtitle: "", course: .general, startHour: 7, duration: 1, date: firstDay)
        ]

        let planned = DayTimelineView.plannedScheduleBlocks(
            tasks: [earlier, later, completed],
            scheduleBlocks: blocks
        )

        XCTAssertEqual(planned.compactMap(\.linkedTaskID), [earlier.id, later.id])
    }

    @MainActor
    func testQuickCommandCreatesScheduledTaskAtPlannedTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 23, hour: 9)))
        let interpretation = CommandInterpreter.interpret(
            "schedule Essay outline tomorrow 4:05 pm 45m",
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(interpretation.intent, .scheduleTask)
        XCTAssertEqual(interpretation.draft.title, "Essay outline")
        XCTAssertEqual(interpretation.draft.estimatedMinutes, 45)

        let state = AppState(seedData: false, persistenceEnabled: false)
        let task = state.createScheduledTask(from: interpretation.draft)
        let block = try XCTUnwrap(state.scheduleBlocks.first(where: { $0.linkedTaskID == task.id }))
        XCTAssertEqual(block.startHour, 16 + 5.0 / 60.0, accuracy: 0.0001)
        XCTAssertEqual(block.duration, 0.75)
        XCTAssertTrue(calendar.isDate(block.date, inSameDayAs: interpretation.draft.dueDate))

        let second = CommandInterpreter.interpret(
            "/schedule Essay outline tomorrow at 7:30 pm 30m",
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(
            state.scheduleTask(
                matching: "Essay outline",
                to: second.draft.dueDate,
                durationMinutes: second.draft.estimatedMinutes
            )?.id,
            task.id
        )
        let blocks = state.scheduleBlocks.filter { $0.linkedTaskID == task.id }
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.last?.startHour, 19.5)
        XCTAssertEqual(blocks.last?.duration, 0.5)
        XCTAssertEqual(state.tasks.first(where: { $0.id == task.id })?.dueDate, interpretation.draft.dueDate)
    }

    @MainActor
    func testNaturalLanguageKeepsDueDateSeparateFromPlannedTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 10)))
        let interpretation = CommandInterpreter.interpret(
            "calc worksheet from class tomorrrow schedule tonight 8:30PM",
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(interpretation.intent, .scheduleTask)
        XCTAssertEqual(interpretation.draft.title, "Worksheet from class")
        XCTAssertEqual(interpretation.draft.course, .calculus)
        XCTAssertEqual(calendar.component(.day, from: interpretation.draft.dueDate), 26)
        XCTAssertEqual(calendar.component(.day, from: interpretation.plannedDate), 25)
        XCTAssertEqual(calendar.component(.hour, from: interpretation.plannedDate), 20)
        XCTAssertEqual(calendar.component(.minute, from: interpretation.plannedDate), 30)

        let state = AppState(seedData: false, persistenceEnabled: false)
        let task = state.createScheduledTask(from: interpretation.draft)
        let block = try XCTUnwrap(state.scheduleBlocks.first(where: { $0.linkedTaskID == task.id }))
        XCTAssertEqual(calendar.component(.day, from: task.dueDate), 26)
        XCTAssertEqual(block.startHour, 20.5, accuracy: 0.0001)
        XCTAssertTrue(calendar.isDate(block.date, inSameDayAs: interpretation.plannedDate))
    }

    func testQuickCommandSeparatesExplicitDueTimeFromPlannedTimeInEitherOrder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 10)))

        for command in [
            "Essay due tomorrow 11:45 pm schedule tonight 8:30 pm",
            "schedule Essay tonight 8:30 pm due tomorrow 11:45 pm"
        ] {
            let interpretation = CommandInterpreter.interpret(command, now: now, calendar: calendar)
            let due = calendar.dateComponents([.day, .hour, .minute], from: interpretation.draft.dueDate)
            let planned = calendar.dateComponents([.day, .hour, .minute], from: interpretation.plannedDate)

            XCTAssertEqual(interpretation.intent, .scheduleTask)
            XCTAssertEqual(interpretation.draft.title, "Essay")
            XCTAssertEqual(due.day, 27)
            XCTAssertEqual(due.hour, 23)
            XCTAssertEqual(due.minute, 45)
            XCTAssertEqual(planned.day, 26)
            XCTAssertEqual(planned.hour, 20)
            XCTAssertEqual(planned.minute, 30)
        }
    }

    func testScheduleCommandAcceptsLeadingConnectorsAndSlashCatalogHasHelp() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 23, hour: 9)))

        for connector in ["for", "at", "on"] {
            let interpretation = CommandInterpreter.interpret(
                "schedule \(connector) 4:05 pm Essay outline 45m",
                now: now,
                calendar: calendar
            )
            XCTAssertEqual(interpretation.intent, .scheduleTask)
            XCTAssertEqual(interpretation.draft.title, "Essay outline")
            XCTAssertEqual(calendar.component(.hour, from: interpretation.draft.dueDate), 16)
            XCTAssertEqual(calendar.component(.minute, from: interpretation.draft.dueDate), 5)
        }

        let commands = SlashCommandDefinition.matching("/")
        XCTAssertGreaterThan(commands.count, 10)
        XCTAssertEqual(commands.first(where: { $0.command == "/schedule" })?.detail, "Plan an existing task")
        XCTAssertTrue(SlashCommandDefinition.hasEnteredArgument(in: "/task Essay outline"))
        XCTAssertFalse(SlashCommandDefinition.hasEnteredArgument(in: "/task"))
    }

    @MainActor
    func testSlashSchedulePlansExistingTaskWithoutChangingItsDueDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 23, hour: 9)))
        let dueDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 10)))
        let state = AppState(seedData: false, persistenceEnabled: false)
        let task = state.addTask(title: "Essay outline", dueDate: dueDate, estimatedMinutes: 45)
        let interpretation = CommandInterpreter.interpret(
            "/schedule Essay outline tomorrow at 4:05 pm",
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(interpretation.intent, .scheduleExistingTask(query: "Essay outline"))
        XCTAssertEqual(state.scheduleTask(matching: "Essay outline", to: interpretation.draft.dueDate)?.id, task.id)
        XCTAssertEqual(state.tasks.first(where: { $0.id == task.id })?.dueDate, dueDate)

        let block = try XCTUnwrap(state.scheduleBlocks.first(where: { $0.linkedTaskID == task.id }))
        XCTAssertEqual(block.startHour, 16 + 5.0 / 60.0, accuracy: 0.0001)
        XCTAssertEqual(block.duration, 0.75)
        XCTAssertTrue(calendar.isDate(block.date, inSameDayAs: interpretation.draft.dueDate))
    }

    @MainActor
    func testPlannedWorkloadUsesThirtyHourScheduleInsteadOfDueDates() throws {
        let state = AppState(seedData: false, persistenceEnabled: false)
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: Date())
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        let later = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: day))
        let lateTask = state.addTask(title: "Late study", dueDate: later, estimatedMinutes: 30)
        let earlyTask = state.addTask(title: "Early study", dueDate: later, estimatedMinutes: 45)
        _ = state.addTask(title: "Due only", dueDate: day, estimatedMinutes: 120)
        let boundaryTask = state.addTask(title: "Tomorrow morning", dueDate: later, estimatedMinutes: 90)

        state.schedule(lateTask.id, at: 23.5, on: day)
        state.schedule(earlyTask.id, at: 2, on: nextDay)
        state.schedule(boundaryTask.id, at: 6, on: nextDay)
        state.toggleComplete(lateTask.id)

        XCTAssertEqual(state.plannedWorkload(on: day), 75)
    }

    @MainActor
    func testTaskCanUseMultipleScheduleBlocksAndRemoveOrMoveOne() throws {
        let state = AppState(seedData: false, persistenceEnabled: false)
        let task = state.addTask(title: "Read chapter")
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: Date()))

        state.schedule(task.id, at: 9, on: Date())
        state.schedule(task.id, at: 14.5, on: tomorrow)

        var blocks = state.scheduleBlocks.filter { $0.linkedTaskID == task.id }
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.map(\.startHour), [9, 14.5])

        state.moveScheduleBlock(blocks[0].id, to: 10.25, on: Date())
        XCTAssertEqual(state.scheduleBlocks.first(where: { $0.id == blocks[0].id })?.startHour, 10.25)

        state.deleteScheduleBlock(blocks[0].id)
        blocks = state.scheduleBlocks.filter { $0.linkedTaskID == task.id }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].startHour, 14.5)
        XCTAssertTrue(Calendar.current.isDate(blocks[0].date, inSameDayAs: tomorrow))
        XCTAssertEqual(state.tasks.first(where: { $0.id == task.id })?.scheduledHour, 14.5)
    }

    @MainActor
    func testDeletingTaskRemovesDescendantsAndTheirScheduledBlocks() {
        let state = AppState(seedData: false, persistenceEnabled: false)
        let parent = state.addTask(title: "Essay")
        let child = state.addTask(title: "Outline", parentTaskID: parent.id)
        let grandchild = state.addTask(title: "Sources", parentTaskID: child.id)
        state.schedule(parent.id, at: 9)
        state.schedule(child.id, at: 10)
        state.schedule(grandchild.id, at: 11)
        state.selectedTaskID = child.id
        state.pomodoroLinkedTaskID = grandchild.id

        state.deleteTask(parent.id)

        XCTAssertTrue(state.tasks.isEmpty)
        XCTAssertTrue(state.scheduleBlocks.isEmpty)
        XCTAssertNil(state.selectedTaskID)
        XCTAssertNil(state.pomodoroLinkedTaskID)
    }

    @MainActor
    func testRecurringTaskCreatesExactlyOneNextOccurrenceWhenCompleted() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let dueDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 18)))
        let state = AppState(seedData: false, persistenceEnabled: false)
        let task = state.addTask(title: "Weekly review", dueDate: dueDate, recurrence: .weekly)

        state.toggleComplete(task.id)

        let source = try XCTUnwrap(state.tasks.first(where: { $0.id == task.id }))
        let nextID = try XCTUnwrap(source.nextOccurrenceID)
        let next = try XCTUnwrap(state.tasks.first(where: { $0.id == nextID }))
        XCTAssertTrue(source.isCompleted)
        XCTAssertEqual(next.title, task.title)
        XCTAssertEqual(next.recurrence, .weekly)
        XCTAssertEqual(next.dueDate, try XCTUnwrap(calendar.date(byAdding: .weekOfYear, value: 1, to: dueDate)))

        state.updateTask(task)
        state.toggleComplete(task.id)
        XCTAssertEqual(state.tasks.filter { $0.title == task.title }.count, 2)
    }

    @MainActor
    func testMeetingRenameAndRecurrenceCreateOneUpcomingOccurrence() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let meetingDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 3, hour: 11)))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 12)))
        let state = AppState(seedData: false, persistenceEnabled: false)
        var meeting = state.addMeeting(title: "New meeting", projectID: nil)
        meeting.title = "  Daily study group  "
        meeting.date = meetingDate
        meeting.recurrence = .daily
        state.updateMeeting(meeting)

        state.refreshRecurringItems(now: now)

        let renamed = try XCTUnwrap(state.meetings.first(where: { $0.id == meeting.id }))
        let nextID = try XCTUnwrap(renamed.nextOccurrenceID)
        let next = try XCTUnwrap(state.meetings.first(where: { $0.id == nextID }))
        XCTAssertEqual(renamed.title, "Daily study group")
        XCTAssertEqual(next.title, renamed.title)
        XCTAssertEqual(next.recurrence, .daily)
        XCTAssertEqual(next.date, try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 11, hour: 11))))
        state.refreshRecurringItems(now: now)
        XCTAssertEqual(state.meetings.count, 2)
    }

    @MainActor
    func testUnschedulingClearsThePlanAndCannotBeRestoredByAStaleEditor() throws {
        let state = AppState(seedData: false, persistenceEnabled: false)
        let task = state.addTask(title: "Essay outline")
        state.schedule(task.id, at: 14, on: Date())
        let staleDraft = try XCTUnwrap(state.tasks.first(where: { $0.id == task.id }))

        XCTAssertTrue(state.unschedule(task.id))
        state.updateTask(staleDraft)

        XCTAssertFalse(state.scheduleBlocks.contains(where: { $0.linkedTaskID == task.id }))
        XCTAssertNil(state.tasks.first(where: { $0.id == task.id })?.scheduledHour)
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

    func testQuickCommandEscapesSubjectsAndParserTerms() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 9)))

        let draft = CommandParser.parse("\\AP Calculus \\tomorrow \\4pm \\45m \\#chem", now: now, calendar: calendar)

        XCTAssertEqual(draft.title, "AP Calculus tomorrow 4pm 45m #chem")
        XCTAssertEqual(draft.course, .general)
        XCTAssertTrue(draft.recognizedTokens.isEmpty)

        let scheduled = CommandInterpreter.interpret("\\AP Calculus review schedule tomorrow", now: now, calendar: calendar)
        XCTAssertEqual(scheduled.intent, .scheduleTask)
        XCTAssertEqual(scheduled.draft.title, "AP Calculus review")
        XCTAssertEqual(scheduled.draft.course, .general)
        XCTAssertEqual(calendar.component(.day, from: scheduled.plannedDate), 18)
    }

    func testCommandInterpreterEscapesActionsAndPayloads() {
        let timer = CommandInterpreter.interpret("\\start timer")
        let schedule = CommandInterpreter.interpret("\\schedule homework tomorrow")
        let capture = CommandInterpreter.interpret("/capture \\tomorrow")
        let search = CommandInterpreter.interpret("search \\chem")

        XCTAssertEqual(timer.intent, .createTask)
        XCTAssertEqual(timer.draft.title, "Start timer")
        XCTAssertEqual(schedule.intent, .createTask)
        XCTAssertEqual(schedule.draft.title, "Schedule homework")
        XCTAssertEqual(capture.intent, .capture(text: "tomorrow"))
        XCTAssertEqual(search.intent, .search(query: "chem"))
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

import Foundation
import SwiftUI
@preconcurrency import UserNotifications

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var selectedSection: HubSection = .today
    @Published var spaces: [Course]
    @Published var tasks: [HubTask]
    @Published var scheduleBlocks: [ScheduleBlock]
    @Published var projects: [HubProject]
    @Published var notes: [HubNote]
    @Published var journalEntries: [JournalEntry]
    @Published var meetings: [MeetingRecord]
    @Published var reminders: [HubReminder]
    @Published var files: [HubFileItem]
    @Published var captures: [WhiteboardCapture]

    @Published var selectedTaskID: UUID?
    @Published var selectedProjectID: UUID?
    @Published var selectedNoteID: UUID?
    @Published var selectedJournalID: UUID?
    @Published var selectedMeetingID: UUID?
    @Published var selectedFileID: UUID?
    @Published var selectedSpaceID: String?
    @Published var openNoteIDs: [UUID] = []
    @Published var taskCourseFilter: Course? = nil

    @Published var isCommandHubVisible = true
    @Published var isQuickCommandPresented = false
    @Published var pomodoroRemaining = 25 * 60
    @Published var pomodoroRunning = false
    @Published var focusTimerMode: FocusTimerMode = .countdown
    @Published var focusTimerElapsed = 0
    @Published var pomodoroLinkedTaskID: UUID?
    @Published var lastExportURLs: [URL] = []
    @Published var exportedFiles: [URL] = []
    @Published var statusMessage: String?
    @Published var cloudSyncStatus: CloudSyncStatus = .localOnly
    @Published var isCloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isCloudSyncEnabled, forKey: "cloudSyncEnabled")
            if isCloudSyncEnabled {
                Task { await syncNow() }
            } else {
                cloudPushTask?.cancel()
                cloudSyncStatus = .localOnly
            }
        }
    }
    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearanceMode") }
    }

    private var pomodoroTimer: Timer?
    private var countdownEndDate: Date?
    private var stopwatchStartedAt: Date?
    private var stopwatchBaseElapsed = 0
    private var cloudPushTask: Task<Void, Never>?
    private var workspaceModifiedAt = Date.distantPast
    private var isApplyingRemoteSnapshot = false
    private let persistenceEnabled: Bool

    init(seedData: Bool = true, persistenceEnabled: Bool = true) {
        self.persistenceEnabled = persistenceEnabled
        isCloudSyncEnabled = UserDefaults.standard.bool(forKey: "cloudSyncEnabled")
        appearance = AppearanceMode(
            rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        ) ?? .system

        let storedSnapshot = seedData ? WorkspaceStorage.load() : nil
        if let snapshot = storedSnapshot {
            workspaceModifiedAt = snapshot.modifiedAt
            spaces = snapshot.spaces
            tasks = snapshot.tasks
            scheduleBlocks = snapshot.scheduleBlocks
            projects = snapshot.projects
            notes = snapshot.notes
            journalEntries = snapshot.journalEntries
            meetings = snapshot.meetings
            reminders = snapshot.reminders
            files = snapshot.files
            captures = snapshot.captures
        } else if seedData {
            let seed = Self.makeSeedSnapshot()
            workspaceModifiedAt = seed.modifiedAt
            spaces = seed.spaces
            tasks = seed.tasks
            scheduleBlocks = seed.scheduleBlocks
            projects = seed.projects
            notes = seed.notes
            journalEntries = seed.journalEntries
            meetings = seed.meetings
            reminders = seed.reminders
            files = seed.files
            captures = seed.captures
        } else {
            spaces = Course.allCases
            tasks = []
            scheduleBlocks = []
            projects = []
            notes = []
            journalEntries = []
            meetings = []
            reminders = []
            files = []
            captures = []
        }

        selectedTaskID = tasks.first(where: { !$0.isCompleted })?.id
        selectedProjectID = projects.first?.id
        selectedNoteID = notes.first?.id
        selectedJournalID = journalEntries.first?.id
        selectedMeetingID = meetings.first?.id
        selectedFileID = files.first?.id
        if let selectedNoteID { openNoteIDs = [selectedNoteID] }
        if let timer = storedSnapshot?.focusTimer { restoreFocusTimer(from: timer) }
        try? WorkspaceStorage.prepareDirectories()
        refreshExports()
        if seedData, storedSnapshot == nil { persist() }
        if isCloudSyncEnabled {
            if CloudSyncAvailability.isConfigured {
                cloudSyncStatus = .checking
                Task { await syncNow() }
            } else {
                cloudSyncStatus = .unavailable("This build is not signed for iCloud; local saving is still active.")
            }
        }
    }

    var selectedTask: HubTask? { tasks.first(where: { $0.id == selectedTaskID }) }
    var selectedProject: HubProject? { projects.first(where: { $0.id == selectedProjectID }) }
    var selectedNote: HubNote? { notes.first(where: { $0.id == selectedNoteID }) }
    var selectedJournal: JournalEntry? { journalEntries.first(where: { $0.id == selectedJournalID }) }
    var selectedMeeting: MeetingRecord? { meetings.first(where: { $0.id == selectedMeetingID }) }
    var selectedFile: HubFileItem? { files.first(where: { $0.id == selectedFileID }) }

    var defaultSpace: Course {
        spaces.first(where: { $0.id == Course.general.id }) ?? spaces.first ?? .general
    }

    private func canonicalSpace(_ space: Course) -> Course {
        spaces.first(where: { $0.id == space.id }) ?? defaultSpace
    }

    var pomodoroLabel: String {
        let seconds = focusTimerMode == .countdown ? pomodoroRemaining : focusTimerElapsed
        if seconds >= 3600 {
            return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var focusTimerTitle: String { focusTimerMode == .countdown ? "Countdown" : "Stopwatch" }

    var cloudSyncDetail: String? {
        switch cloudSyncStatus {
        case .synced(let date): "Last synced \(date.formatted(date: .omitted, time: .shortened))"
        case .unavailable(let message): message
        default: nil
        }
    }

    func toggleCommandHub() {
        withAnimation(.easeInOut(duration: 0.22)) { isCommandHubVisible.toggle() }
    }

    func navigate(to section: HubSection) {
        selectedSection = section
    }

    // MARK: - Spaces

    @discardableResult
    func addSpace(title: String, colorHex: UInt32) -> Course? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !spaces.contains(where: { $0.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else { return nil }
        let space = Course(title: trimmed, colorHex: colorHex)
        spaces.append(space)
        persist()
        return space
    }

    func updateSpace(_ space: Course) {
        let trimmed = space.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = spaces.firstIndex(where: { $0.id == space.id }),
              !spaces.contains(where: { $0.id != space.id && $0.title.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) else { return }

        var updated = space
        updated.title = trimmed
        spaces[index] = updated
        for taskIndex in tasks.indices where tasks[taskIndex].course.id == updated.id { tasks[taskIndex].course = updated }
        for blockIndex in scheduleBlocks.indices where scheduleBlocks[blockIndex].course.id == updated.id {
            scheduleBlocks[blockIndex].course = updated
            if scheduleBlocks[blockIndex].linkedTaskID != nil { scheduleBlocks[blockIndex].subtitle = updated.title }
        }
        for projectIndex in projects.indices where projects[projectIndex].course.id == updated.id { projects[projectIndex].course = updated }
        for noteIndex in notes.indices where notes[noteIndex].course.id == updated.id {
            notes[noteIndex].course = updated
            saveNoteFile(notes[noteIndex])
        }
        for fileIndex in files.indices where files[fileIndex].course.id == updated.id { files[fileIndex].course = updated }
        if taskCourseFilter?.id == updated.id { taskCourseFilter = updated }
        persist()
    }

    func moveSpaces(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        spaces.move(fromOffsets: offsets, toOffset: destination)
        persist()
    }

    func moveSpace(_ id: String, by offset: Int) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard spaces.indices.contains(destination) else { return }
        spaces.swapAt(index, destination)
        persist()
    }

    func deleteSpace(_ id: String, reassignTo replacementID: String) {
        guard spaces.count > 1,
              let replacement = spaces.first(where: { $0.id == replacementID && $0.id != id }),
              spaces.contains(where: { $0.id == id }) else { return }

        for taskIndex in tasks.indices where tasks[taskIndex].course.id == id { tasks[taskIndex].course = replacement }
        for blockIndex in scheduleBlocks.indices where scheduleBlocks[blockIndex].course.id == id {
            scheduleBlocks[blockIndex].course = replacement
            if scheduleBlocks[blockIndex].linkedTaskID != nil { scheduleBlocks[blockIndex].subtitle = replacement.title }
        }
        for projectIndex in projects.indices where projects[projectIndex].course.id == id { projects[projectIndex].course = replacement }
        for noteIndex in notes.indices where notes[noteIndex].course.id == id {
            notes[noteIndex].course = replacement
            saveNoteFile(notes[noteIndex])
        }
        for fileIndex in files.indices where files[fileIndex].course.id == id { files[fileIndex].course = replacement }
        spaces.removeAll(where: { $0.id == id })
        if taskCourseFilter?.id == id { taskCourseFilter = replacement }
        persist()
    }

    func deleteSpaceAndContents(_ id: String) {
        guard spaces.count > 1, spaces.contains(where: { $0.id == id }) else { return }

        var deletedTaskIDs = Set(tasks.filter { $0.course.id == id }.map(\.id))
        while true {
            let childIDs = Set(tasks.filter { $0.parentTaskID.map(deletedTaskIDs.contains) == true }.map(\.id))
            let previousCount = deletedTaskIDs.count
            deletedTaskIDs.formUnion(childIDs)
            if deletedTaskIDs.count == previousCount { break }
        }
        let deletedProjectIDs = Set(projects.filter { $0.course.id == id }.map(\.id))
        let deletedNoteIDs = Set(notes.filter { $0.course.id == id }.map(\.id))

        for item in files where item.course.id == id {
            try? FileManager.default.removeItem(at: WorkspaceStorage.fileURL(for: item))
        }
        for note in notes where note.course.id == id {
            try? FileManager.default.removeItem(at: WorkspaceStorage.markdownURL(for: note))
        }

        tasks.removeAll { deletedTaskIDs.contains($0.id) }
        scheduleBlocks.removeAll { $0.course.id == id || $0.linkedTaskID.map(deletedTaskIDs.contains) == true }
        projects.removeAll { $0.course.id == id }
        notes.removeAll { $0.course.id == id }
        files.removeAll { $0.course.id == id }
        spaces.removeAll { $0.id == id }

        for index in tasks.indices {
            if tasks[index].projectID.map(deletedProjectIDs.contains) == true { tasks[index].projectID = nil }
            if tasks[index].linkedNoteID.map(deletedNoteIDs.contains) == true {
                tasks[index].linkedNoteID = nil
                tasks[index].linkedNote = nil
            }
        }
        for index in reminders.indices where reminders[index].linkedTaskID.map(deletedTaskIDs.contains) == true {
            reminders[index].linkedTaskID = nil
        }
        for index in captures.indices {
            if captures[index].linkedTaskID.map(deletedTaskIDs.contains) == true { captures[index].linkedTaskID = nil }
            if captures[index].linkedNoteID.map(deletedNoteIDs.contains) == true { captures[index].linkedNoteID = nil }
        }

        openNoteIDs.removeAll { deletedNoteIDs.contains($0) }
        if selectedTaskID.map(deletedTaskIDs.contains) == true { selectedTaskID = tasks.first?.id }
        if selectedProjectID.map(deletedProjectIDs.contains) == true { selectedProjectID = projects.first?.id }
        if selectedNoteID.map(deletedNoteIDs.contains) == true { selectedNoteID = openNoteIDs.last ?? notes.first?.id }
        if selectedFileID.flatMap({ selectedID in files.first(where: { $0.id == selectedID }) }) == nil { selectedFileID = files.first?.id }
        if taskCourseFilter?.id == id { taskCourseFilter = nil }
        persist()
    }

    func itemCount(in space: Course) -> Int {
        tasks.filter { $0.course.id == space.id }.count
        + projects.filter { $0.course.id == space.id }.count
        + notes.filter { $0.course.id == space.id }.count
        + files.filter { $0.course.id == space.id }.count
    }

    // MARK: - Universal capture

    @discardableResult
    func addCapture(_ text: String) -> WhiteboardCapture {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let capture = WhiteboardCapture(text: trimmed.isEmpty ? "Untitled capture" : trimmed)
        captures.insert(capture, at: 0)
        persist()
        return capture
    }

    func convertCaptureToTask(_ captureID: UUID) {
        guard let index = captures.firstIndex(where: { $0.id == captureID }) else { return }
        let task = addTask(
            title: captures[index].text,
            dueDate: Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date()
        )
        captures[index].linkedTaskID = task.id
        persist()
    }

    func convertCaptureToNote(_ captureID: UUID) {
        guard let index = captures.firstIndex(where: { $0.id == captureID }) else { return }
        let text = captures[index].text
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Captured thought"
        let title = String(firstLine.prefix(48))
        var note = addNote(title: title, folder: "Scratchpad")
        note.markdown = "# \(title)\n\n\(text)\n"
        updateNote(note)
        captures[index].linkedNoteID = note.id
        persist()
    }

    func updateCapture(_ id: UUID, text: String) {
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, captures[index].text != trimmed else { return }
        captures[index].text = trimmed
        persist()
    }

    func deleteCapture(_ id: UUID) {
        captures.removeAll(where: { $0.id == id })
        persist()
    }

    // MARK: - Tasks and calendar

    func select(_ task: HubTask) {
        selectedTaskID = selectedTaskID == task.id ? nil : task.id
    }

    @discardableResult
    func addTask(
        title: String,
        course: Course = .general,
        dueDate: Date = Date(),
        projectID: UUID? = nil,
        parentTaskID: UUID? = nil,
        details: String = ""
    ) -> HubTask {
        let task = HubTask(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled task" : title,
            course: canonicalSpace(course),
            dueDate: dueDate,
            projectID: projectID,
            parentTaskID: parentTaskID,
            details: details
        )
        tasks.insert(task, at: 0)
        selectedTaskID = task.id
        persist()
        return task
    }

    func createTask(from draft: QuickCommandDraft) {
        var task = addTask(title: draft.title, course: draft.course, dueDate: draft.dueDate)
        if let noteName = draft.linkedNote, let note = notes.first(where: { $0.title == noteName.replacingOccurrences(of: ".md", with: "") || $0.title == noteName }) {
            task.linkedNoteID = note.id
            task.linkedNote = noteName
            updateTask(task)
        }
    }

    func updateTask(_ task: HubTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = task
        updated.course = canonicalSpace(task.course)
        tasks[index] = updated
        persist()
    }

    func deleteTask(_ taskID: UUID) {
        tasks.removeAll(where: { $0.id == taskID || $0.parentTaskID == taskID })
        scheduleBlocks.removeAll(where: { $0.linkedTaskID == taskID })
        if selectedTaskID == taskID { selectedTaskID = tasks.first?.id }
        persist()
    }

    func toggleComplete(_ taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].isCompleted.toggle()
        persist()
    }

    func schedule(_ taskID: UUID, at hour: Double = 16, on date: Date = Date()) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].scheduledHour = hour
        let task = tasks[index]
        scheduleBlocks.removeAll(where: { $0.linkedTaskID == taskID && Calendar.current.isDate($0.date, inSameDayAs: date) })
        scheduleBlocks.append(
            ScheduleBlock(
                title: task.title,
                subtitle: task.course.title,
                course: task.course,
                startHour: hour,
                duration: 1,
                date: date,
                linkedTaskID: task.id
            )
        )
        persist()
    }

    @discardableResult
    func rescheduleTask(matching query: String, to date: Date) -> HubTask? {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let index = tasks.firstIndex(where: {
                  !$0.isCompleted && $0.title.localizedCaseInsensitiveContains(normalized)
              }) ?? tasks.firstIndex(where: {
                  $0.title.localizedCaseInsensitiveContains(normalized)
              }) else { return nil }

        tasks[index].dueDate = date
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let scheduledHour = Double(components.hour ?? 16) + Double(components.minute ?? 0) / 60
        tasks[index].scheduledHour = scheduledHour
        let task = tasks[index]
        scheduleBlocks.removeAll(where: { $0.linkedTaskID == task.id })
        scheduleBlocks.append(
            ScheduleBlock(
                title: task.title,
                subtitle: task.course.title,
                course: task.course,
                startHour: scheduledHour,
                duration: 1,
                date: date,
                linkedTaskID: task.id
            )
        )
        selectedTaskID = task.id
        persist()
        return task
    }

    func addScheduleBlock(title: String, course: Course, date: Date, startHour: Double, duration: Double) {
        let course = canonicalSpace(course)
        scheduleBlocks.append(
            ScheduleBlock(title: title, subtitle: course.title, course: course, startHour: startHour, duration: duration, date: date)
        )
        persist()
    }

    func updateScheduleBlock(_ block: ScheduleBlock) {
        guard let index = scheduleBlocks.firstIndex(where: { $0.id == block.id }) else { return }
        var updated = block
        updated.course = canonicalSpace(block.course)
        updated.subtitle = updated.course.title
        updated.startHour = min(24 - 1.0 / 60.0, max(0, block.startHour))
        updated.duration = min(24 - updated.startHour, max(1.0 / 60.0, block.duration))
        scheduleBlocks[index] = updated
        if let taskID = updated.linkedTaskID,
           let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[taskIndex].scheduledHour = updated.startHour
        }
        persist()
    }

    func deleteScheduleBlock(_ id: UUID) {
        scheduleBlocks.removeAll(where: { $0.id == id })
        persist()
    }

    // MARK: - Projects

    @discardableResult
    func addProject(title: String, course: Course, deadline: Date, details: String = "") -> HubProject {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = HubProject(
            title: trimmedTitle.isEmpty ? "Untitled project" : trimmedTitle,
            course: canonicalSpace(course),
            deadline: deadline,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        projects.insert(project, at: 0)
        selectedProjectID = project.id
        persist()
        return project
    }

    func updateProject(_ project: HubProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        var updated = project
        let trimmedTitle = project.title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmedTitle.isEmpty ? "Untitled project" : trimmedTitle
        updated.course = canonicalSpace(project.course)
        projects[index] = updated
        persist()
    }

    func deleteProject(_ id: UUID) {
        projects.removeAll(where: { $0.id == id })
        for index in tasks.indices where tasks[index].projectID == id { tasks[index].projectID = nil }
        selectedProjectID = projects.first?.id
        persist()
    }

    func progress(for projectID: UUID) -> Double {
        let projectTasks = tasks.filter { $0.projectID == projectID }
        guard !projectTasks.isEmpty else { return 0 }
        return Double(projectTasks.filter(\.isCompleted).count) / Double(projectTasks.count)
    }

    // MARK: - Notes

    @discardableResult
    func addNote(title: String = "Untitled note", folder: String = "Inbox", course: Course = .general) -> HubNote {
        let note = HubNote(title: title, folder: folder, markdown: "# \(title)\n\n", course: canonicalSpace(course))
        notes.insert(note, at: 0)
        selectedNoteID = note.id
        openNote(note.id)
        saveNoteFile(note)
        persist()
        return note
    }

    func updateNote(_ note: HubNote) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let previous = notes[index]
        var updated = note
        updated.course = canonicalSpace(note.course)
        updated.modifiedAt = Date()
        notes[index] = updated
        if persistenceEnabled {
            do {
                _ = try WorkspaceStorage.writeMarkdown(updated)
                let previousURL = WorkspaceStorage.markdownURL(for: previous)
                let updatedURL = WorkspaceStorage.markdownURL(for: updated)
                if previousURL != updatedURL, FileManager.default.fileExists(atPath: previousURL.path) {
                    try FileManager.default.removeItem(at: previousURL)
                }
            } catch {
                statusMessage = "Could not write Markdown: \(error.localizedDescription)"
            }
        }
        persist()
    }

    func deleteNote(_ id: UUID) {
        if persistenceEnabled, let note = notes.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: WorkspaceStorage.markdownURL(for: note))
        }
        notes.removeAll(where: { $0.id == id })
        openNoteIDs.removeAll(where: { $0 == id })
        if selectedNoteID == id { selectedNoteID = openNoteIDs.last ?? notes.first?.id }
        persist()
    }

    func openNote(_ id: UUID) {
        if !openNoteIDs.contains(id) { openNoteIDs.append(id) }
        selectedNoteID = id
    }

    func closeNote(_ id: UUID) {
        openNoteIDs.removeAll(where: { $0 == id })
        if selectedNoteID == id { selectedNoteID = openNoteIDs.last }
    }

    func toggleLink(noteID: UUID, taskID: UUID) {
        guard let noteIndex = notes.firstIndex(where: { $0.id == noteID }),
              let taskIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        if notes[noteIndex].linkedTaskIDs.contains(taskID) {
            notes[noteIndex].linkedTaskIDs.removeAll(where: { $0 == taskID })
            if tasks[taskIndex].linkedNoteID == noteID { tasks[taskIndex].linkedNoteID = nil }
        } else {
            notes[noteIndex].linkedTaskIDs.append(taskID)
            tasks[taskIndex].linkedNoteID = noteID
            tasks[taskIndex].linkedNote = notes[noteIndex].title + ".md"
        }
        notes[noteIndex].modifiedAt = Date()
        saveNoteFile(notes[noteIndex])
        persist()
    }

    func noteURL(_ id: UUID) -> URL? {
        guard let note = notes.first(where: { $0.id == id }) else { return nil }
        return try? WorkspaceStorage.writeMarkdown(note)
    }

    // MARK: - Journal

    @discardableResult
    func addJournalEntry(date: Date = Date()) -> JournalEntry {
        let entry = JournalEntry(
            date: date,
            title: date.formatted(date: .long, time: .omitted),
            isDateLinked: true
        )
        journalEntries.insert(entry, at: 0)
        selectedJournalID = entry.id
        persist()
        return entry
    }

    @discardableResult
    func addJournalMemo() -> JournalEntry {
        let entry = JournalEntry(title: "Untitled memo", isDateLinked: false)
        journalEntries.insert(entry, at: 0)
        selectedJournalID = entry.id
        persist()
        return entry
    }

    func updateJournal(_ entry: JournalEntry) {
        guard let index = journalEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        journalEntries[index] = entry
        persist()
    }

    func deleteJournal(_ id: UUID) {
        journalEntries.removeAll(where: { $0.id == id })
        selectedJournalID = journalEntries.first?.id
        persist()
    }

    // MARK: - Meetings

    @discardableResult
    func addMeeting(title: String, projectID: UUID?) -> MeetingRecord {
        let meeting = MeetingRecord(title: title.isEmpty ? "New meeting" : title, projectID: projectID)
        meetings.insert(meeting, at: 0)
        selectedMeetingID = meeting.id
        persist()
        return meeting
    }

    func updateMeeting(_ meeting: MeetingRecord) {
        guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else { return }
        meetings[index] = meeting
        persist()
    }

    func deleteMeeting(_ id: UUID) {
        meetings.removeAll(where: { $0.id == id })
        selectedMeetingID = meetings.first?.id
        persist()
    }

    func generateMeetingSummary(_ id: UUID) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        let lines = meetings[index].transcript
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let actionLines = lines.filter { $0.lowercased().hasPrefix("todo:") || $0.hasPrefix("- [ ]") }
        let summaryLines = lines.filter { !actionLines.contains($0) }.prefix(3)
        meetings[index].summary = summaryLines.isEmpty
            ? "Add meeting notes or a transcript to generate a summary."
            : summaryLines.joined(separator: "\n")

        let projectID = meetings[index].projectID
        let course = projects.first(where: { $0.id == projectID })?.course ?? .general
        for line in actionLines {
            let title = line
                .replacingOccurrences(of: "TODO:", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "- [ ]", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let existing = tasks.first(where: { $0.title.caseInsensitiveCompare(title) == .orderedSame && $0.projectID == projectID }) {
                if !meetings[index].actionTaskIDs.contains(existing.id) { meetings[index].actionTaskIDs.append(existing.id) }
            } else {
                let task = addTask(title: title, course: course, dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(), projectID: projectID)
                meetings[index].actionTaskIDs.append(task.id)
            }
        }
        persist()
    }

    // MARK: - Reminders

    func addReminder(title: String, dueDate: Date, linkedTaskID: UUID? = nil) {
        let reminder = HubReminder(title: title.isEmpty ? "Reminder" : title, dueDate: dueDate, linkedTaskID: linkedTaskID)
        reminders.insert(reminder, at: 0)
        scheduleNotification(for: reminder)
        persist()
    }

    func toggleReminder(_ id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].isCompleted.toggle()
        persist()
    }

    func deleteReminder(_ id: UUID) {
        reminders.removeAll(where: { $0.id == id })
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        persist()
    }

    // MARK: - Files and export

    func importFile(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            var item = try WorkspaceStorage.importFile(from: url)
            item.course = defaultSpace
            files.insert(item, at: 0)
            selectedFileID = item.id
            statusMessage = "Imported \(item.displayName)"
            persist()
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func updateFile(_ item: HubFileItem) {
        guard let index = files.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.course = canonicalSpace(item.course)
        files[index] = updated
        persist()
    }

    func deleteFile(_ id: UUID) {
        if let item = files.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: WorkspaceStorage.fileURL(for: item))
        }
        files.removeAll(where: { $0.id == id })
        selectedFileID = files.first?.id
        persist()
    }

    func exportWorkspace() {
        do {
            lastExportURLs = try WorkspaceStorage.export(tasks: tasks, projects: projects)
            refreshExports()
            statusMessage = "Exported CSV and Markdown"
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func exportNote(_ note: HubNote) -> [URL] {
        do {
            let urls = try WorkspaceStorage.export(note: note)
            lastExportURLs = urls
            refreshExports()
            statusMessage = "Exported DOCX, PDF, RTF, and CSV"
            return urls
        } catch {
            statusMessage = "Note export failed: \(error.localizedDescription)"
            return []
        }
    }

    func refreshExports() {
        exportedFiles = WorkspaceStorage.exportedFiles()
    }

    func deleteExport(_ url: URL) {
        do {
            try WorkspaceStorage.deleteExport(at: url)
            lastExportURLs.removeAll(where: { $0.standardizedFileURL == url.standardizedFileURL })
            refreshExports()
            statusMessage = "Deleted \(url.lastPathComponent)"
        } catch {
            statusMessage = "Could not delete export: \(error.localizedDescription)"
        }
    }

    func deleteAllExports() {
        do {
            try WorkspaceStorage.deleteAllExports()
            lastExportURLs = []
            refreshExports()
            statusMessage = "Deleted all exports"
        } catch {
            statusMessage = "Could not clear exports: \(error.localizedDescription)"
        }
    }

    // MARK: - Pomodoro

    func togglePomodoro() {
        if pomodoroRunning {
            updateFocusTimerDisplay()
            pomodoroRunning = false
            if focusTimerMode == .countdown {
                countdownEndDate = nil
            } else {
                stopwatchBaseElapsed = focusTimerElapsed
                stopwatchStartedAt = nil
            }
            pomodoroTimer?.invalidate()
            pomodoroTimer = nil
        } else {
            pomodoroRunning = true
            if focusTimerMode == .countdown {
                if pomodoroRemaining <= 0 { pomodoroRemaining = 25 * 60 }
                countdownEndDate = Date().addingTimeInterval(TimeInterval(pomodoroRemaining))
            } else {
                stopwatchStartedAt = Date()
            }
            startFocusTimerTicks()
        }
        persist()
    }

    func resetPomodoro(minutes: Int = 25) {
        pomodoroTimer?.invalidate()
        pomodoroTimer = nil
        pomodoroRunning = false
        focusTimerMode = .countdown
        pomodoroRemaining = min(24 * 60, max(1, minutes)) * 60
        countdownEndDate = nil
        persist()
    }

    func resetStopwatch() {
        pomodoroTimer?.invalidate()
        pomodoroTimer = nil
        pomodoroRunning = false
        focusTimerMode = .stopwatch
        focusTimerElapsed = 0
        stopwatchBaseElapsed = 0
        stopwatchStartedAt = nil
        persist()
    }

    func startFocusTimer(_ command: FocusTimerCommand) {
        switch command {
        case .countdown(let seconds):
            pomodoroTimer?.invalidate()
            focusTimerMode = .countdown
            pomodoroRemaining = seconds
            countdownEndDate = Date().addingTimeInterval(TimeInterval(seconds))
            stopwatchStartedAt = nil
            pomodoroRunning = true
            statusMessage = "Started \(durationLabel(seconds)) countdown"
        case .stopwatch:
            pomodoroTimer?.invalidate()
            focusTimerMode = .stopwatch
            focusTimerElapsed = 0
            stopwatchBaseElapsed = 0
            stopwatchStartedAt = Date()
            countdownEndDate = nil
            pomodoroRunning = true
            statusMessage = "Started stopwatch"
        }
        startFocusTimerTicks()
        persist()
    }

    private func startFocusTimerTicks() {
        pomodoroTimer?.invalidate()
        pomodoroTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pomodoroTick() }
        }
    }

    private func pomodoroTick() {
        guard pomodoroRunning else { return }
        updateFocusTimerDisplay()
        if focusTimerMode == .countdown, pomodoroRemaining <= 0 {
            pomodoroRunning = false
            pomodoroTimer?.invalidate()
            pomodoroTimer = nil
            countdownEndDate = nil
            statusMessage = "Countdown complete"
            let notification = HubReminder(title: "Focus timer complete", dueDate: Date().addingTimeInterval(1))
            scheduleNotification(for: notification)
            persist()
        }
    }

    private func updateFocusTimerDisplay(now: Date = Date()) {
        if focusTimerMode == .countdown, let countdownEndDate {
            pomodoroRemaining = max(0, Int(ceil(countdownEndDate.timeIntervalSince(now))))
        } else if focusTimerMode == .stopwatch, let stopwatchStartedAt {
            focusTimerElapsed = stopwatchBaseElapsed + max(0, Int(now.timeIntervalSince(stopwatchStartedAt)))
        }
    }

    private func durationLabel(_ seconds: Int) -> String {
        if seconds.isMultiple(of: 3600) { return "\(seconds / 3600)-hour" }
        if seconds.isMultiple(of: 60) { return "\(seconds / 60)-minute" }
        return "\(seconds)-second"
    }

    private var focusTimerSnapshot: FocusTimerSnapshot {
        FocusTimerSnapshot(
            mode: focusTimerMode,
            isRunning: pomodoroRunning,
            countdownRemaining: pomodoroRemaining,
            countdownEndDate: countdownEndDate,
            stopwatchElapsed: stopwatchBaseElapsed,
            stopwatchStartedAt: stopwatchStartedAt
        )
    }

    private func restoreFocusTimer(from snapshot: FocusTimerSnapshot) {
        pomodoroTimer?.invalidate()
        focusTimerMode = snapshot.mode
        pomodoroRunning = snapshot.isRunning
        pomodoroRemaining = snapshot.countdownRemaining
        countdownEndDate = snapshot.countdownEndDate
        stopwatchBaseElapsed = snapshot.stopwatchElapsed
        focusTimerElapsed = snapshot.stopwatchElapsed
        stopwatchStartedAt = snapshot.stopwatchStartedAt

        if focusTimerMode == .countdown, pomodoroRunning {
            let end = countdownEndDate ?? Date().addingTimeInterval(TimeInterval(pomodoroRemaining))
            countdownEndDate = end
            pomodoroRemaining = max(0, Int(ceil(end.timeIntervalSinceNow)))
            if pomodoroRemaining == 0 { pomodoroRunning = false; countdownEndDate = nil }
        } else if focusTimerMode == .stopwatch, pomodoroRunning {
            let start = stopwatchStartedAt ?? Date()
            stopwatchStartedAt = start
            focusTimerElapsed = stopwatchBaseElapsed + max(0, Int(Date().timeIntervalSince(start)))
        }

        if pomodoroRunning { startFocusTimerTicks() }
    }

    // MARK: - Persistence

    func persist() {
        guard persistenceEnabled else { return }
        workspaceModifiedAt = Date()
        let snapshot = currentSnapshot()
        do {
            try WorkspaceStorage.save(snapshot)
            scheduleCloudPushIfNeeded()
        } catch {
            statusMessage = "Could not save workspace: \(error.localizedDescription)"
        }
    }

    func syncNow() async {
        guard isCloudSyncEnabled else {
            cloudSyncStatus = .localOnly
            return
        }
        guard CloudSyncAvailability.isConfigured else {
            cloudSyncStatus = .unavailable("This build is not signed for iCloud; local saving is still active.")
            return
        }
        cloudSyncStatus = .checking
        do {
            guard try await CloudSyncService.shared.accountIsAvailable() else {
                cloudSyncStatus = .unavailable("Sign in to iCloud to sync.")
                return
            }
            cloudSyncStatus = .syncing
            let local = currentSnapshot()
            if let remote = try await CloudSyncService.shared.pull(), remote.modifiedAt > local.modifiedAt {
                applyRemoteSnapshot(remote)
            } else {
                try await CloudSyncService.shared.push(local)
            }
            cloudSyncStatus = .synced(Date())
        } catch {
            cloudSyncStatus = .unavailable(error.localizedDescription)
        }
    }

    private func currentSnapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            modifiedAt: workspaceModifiedAt,
            spaces: spaces,
            tasks: tasks,
            scheduleBlocks: scheduleBlocks,
            projects: projects,
            notes: notes,
            journalEntries: journalEntries,
            meetings: meetings,
            reminders: reminders,
            files: files,
            captures: captures,
            focusTimer: focusTimerSnapshot
        )
    }

    private func scheduleCloudPushIfNeeded() {
        guard isCloudSyncEnabled,
              CloudSyncAvailability.isConfigured,
              !isApplyingRemoteSnapshot else { return }
        cloudPushTask?.cancel()
        cloudPushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            let snapshot = self.currentSnapshot()
            self.cloudSyncStatus = .syncing
            do {
                try await CloudSyncService.shared.push(snapshot)
                guard !Task.isCancelled else { return }
                self.cloudSyncStatus = .synced(Date())
            } catch {
                guard !Task.isCancelled else { return }
                self.cloudSyncStatus = .unavailable(error.localizedDescription)
            }
        }
    }

    private func applyRemoteSnapshot(_ snapshot: WorkspaceSnapshot) {
        isApplyingRemoteSnapshot = true
        workspaceModifiedAt = snapshot.modifiedAt
        spaces = snapshot.spaces
        tasks = snapshot.tasks
        scheduleBlocks = snapshot.scheduleBlocks
        projects = snapshot.projects
        notes = snapshot.notes
        journalEntries = snapshot.journalEntries
        meetings = snapshot.meetings
        reminders = snapshot.reminders
        files = snapshot.files
        captures = snapshot.captures
        restoreFocusTimer(from: snapshot.focusTimer ?? .idlePomodoro)

        if !tasks.contains(where: { $0.id == selectedTaskID }) { selectedTaskID = tasks.first?.id }
        if !projects.contains(where: { $0.id == selectedProjectID }) { selectedProjectID = projects.first?.id }
        if !notes.contains(where: { $0.id == selectedNoteID }) { selectedNoteID = notes.first?.id }
        if !journalEntries.contains(where: { $0.id == selectedJournalID }) { selectedJournalID = journalEntries.first?.id }
        if !meetings.contains(where: { $0.id == selectedMeetingID }) { selectedMeetingID = meetings.first?.id }
        if !files.contains(where: { $0.id == selectedFileID }) { selectedFileID = files.first?.id }
        if let spaceID = selectedSpaceID, !spaces.contains(where: { $0.id == spaceID }) {
            selectedSpaceID = spaces.first?.id
        }
        openNoteIDs.removeAll { id in !notes.contains(where: { $0.id == id }) }

        do {
            try WorkspaceStorage.save(snapshot)
            for note in notes { saveNoteFile(note) }
            statusMessage = "Updated from iCloud"
        } catch {
            statusMessage = "Could not save workspace: \(error.localizedDescription)"
        }
        isApplyingRemoteSnapshot = false
    }

    private func saveNoteFile(_ note: HubNote) {
        guard persistenceEnabled else { return }
        do { _ = try WorkspaceStorage.writeMarkdown(note) }
        catch { statusMessage = "Could not write Markdown: \(error.localizedDescription)" }
    }

    private func scheduleNotification(for reminder: HubReminder) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted, reminder.dueDate > Date() else { return }
            let content = UNMutableNotificationContent()
            content.title = "Student Hub"
            content.body = reminder.title
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.dueDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: trigger)
            center.add(request)
        }
    }

    private static func makeSeedSnapshot() -> WorkspaceSnapshot {
        let tournament = HubProject(
            title: "Summer Debate Tournament",
            course: .debate,
            deadline: date(days: 8, hour: 18),
            details: "Prepare the case, evidence packet, and practice schedule."
        )
        let scienceFair = HubProject(
            title: "Science Fair",
            course: .chemistry,
            deadline: date(days: 21, hour: 17),
            details: "Research question, experiment, report, and presentation."
        )

        let labNote = HubNote(
            title: "Lab Notes",
            folder: "Chemistry",
            markdown: "# Lab Notes\n\n## Reaction\n\nRecord observations here.\n",
            course: .chemistry
        )
        let rebuttalNote = HubNote(
            title: "Rebuttal Notes",
            folder: "Debate",
            markdown: "# Rebuttal Notes\n\n- Evidence to verify\n- Practice cross-examination\n",
            course: .debate
        )

        let tasks = [
            HubTask(title: "Stoichiometry problem set", course: .chemistry, dueDate: date(hour: 17), projectID: scienceFair.id),
            HubTask(title: "Limits worksheet", course: .calculus, dueDate: date(hour: 19)),
            HubTask(title: "Court case prep", course: .debate, dueDate: date(hour: 23, minute: 59), projectID: tournament.id, linkedNoteID: rebuttalNote.id, project: tournament.title, linkedNote: "Rebuttal Notes.md"),
            HubTask(title: "Read Chapter 4", course: .chemistry, dueDate: date(hour: 21, minute: 30), linkedNoteID: labNote.id, linkedNote: "Lab Notes.md")
        ]
        let caseTask = tasks[2]
        var notes = [labNote, rebuttalNote]
        notes[1].linkedTaskIDs = [caseTask.id]

        let schedule = [
            ScheduleBlock(title: "Chemistry Lab", subtitle: "Room 202", course: .chemistry, startHour: 10, duration: 1.25, date: Date()),
            ScheduleBlock(title: "AP Calculus AB", subtitle: "Room 300", course: .calculus, startHour: 13, duration: 1.25, date: Date()),
            ScheduleBlock(title: "Debate Practice", subtitle: "Room 110", course: .debate, startHour: 15.5, duration: 1.5, date: Date(), linkedTaskID: caseTask.id)
        ]

        let meeting = MeetingRecord(
            title: "Tournament planning",
            projectID: tournament.id,
            transcript: "We agreed to finish the evidence packet this week.\nPractice on Saturday afternoon.\nTODO: Find two newer sources\n- [ ] Draft cross-examination questions"
        )
        return WorkspaceSnapshot(
            tasks: tasks,
            scheduleBlocks: schedule,
            projects: [tournament, scienceFair],
            notes: notes,
            journalEntries: [JournalEntry(title: "First day using Student Hub", body: "Today I set up my classes and priorities.", mood: 4)],
            meetings: [meeting],
            reminders: [HubReminder(title: "Bring lab goggles", dueDate: date(days: 1, hour: 7, minute: 30))],
            files: [],
            captures: [WhiteboardCapture(text: "Ask debate coach about evidence rules", linkedTaskID: caseTask.id)]
        )
    }

    private static func date(days: Int = 0, hour: Int, minute: Int = 0) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

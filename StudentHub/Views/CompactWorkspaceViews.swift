import SwiftUI
import UniformTypeIdentifiers

struct CompactWorkspaceContentView: View {
    let section: HubSection

    var body: some View {
        Group {
            switch section {
            case .today: DayTimelineView()
            case .inbox: CompactTasksView(inboxOnly: true)
            case .calendar: CompactCalendarView()
            case .tasks: CompactTasksView(inboxOnly: false)
            case .projects: CompactProjectsView()
            case .notes: CompactNotesView()
            case .files: CompactFilesView()
            case .journal: CompactJournalView()
            case .meetings: CompactMeetingsView()
            case .reminders: CompactRemindersView()
            case .pomodoro: PomodoroWorkspaceView()
            case .export: CompactExportView()
            case .spaceHome: SpaceWorkspaceView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CompactTasksView: View {
    @EnvironmentObject private var appState: AppState
    let inboxOnly: Bool
    @State private var title = ""
    @State private var course: Course = .general
    @State private var editingTaskID: UUID?

    private var visibleTasks: [HubTask] {
        appState.tasks
            .filter { task in
                let inboxMatch = !inboxOnly || (task.projectID == nil && task.parentTaskID == nil)
                let courseMatch = appState.taskCourseFilter == nil || task.course == appState.taskCourseFilter
                return inboxMatch && courseMatch
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HubPageHeader(
                    eyebrow: inboxOnly ? "Capture" : "Plan",
                    title: inboxOnly ? "Inbox" : (appState.taskCourseFilter?.title ?? "All tasks"),
                    subtitle: "Tap a task for dates, links, details, and subtasks."
                )
                VStack(spacing: 10) {
                    HStack {
                        TextField("Add a task", text: $title)
                            .textFieldStyle(.plain)
                            .onSubmit(addTask)
                        Button("Add", action: addTask)
                            .buttonStyle(HubProminentButtonStyle())
                    }
                    Divider()
                    Picker("Course", selection: $course) {
                        ForEach(appState.spaces) { Text($0.title).tag($0) }
                    }
                }
                .padding(14)
                .hubPanel(cornerRadius: 14)

                ForEach(visibleTasks) { task in
                    HStack(spacing: 11) {
                        Button { appState.toggleComplete(task.id) } label: {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(task.isCompleted ? HubPalette.success : task.course.accent)
                        }
                        .buttonStyle(.plain)
                        Button {
                            editingTaskID = task.id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.title).font(.system(size: 14, weight: .semibold)).strikethrough(task.isCompleted)
                                Text("\(task.course.title) • \(task.dueDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(HubPalette.secondaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Image(systemName: "chevron.right").foregroundStyle(HubPalette.tertiaryText)
                    }
                    .padding(13)
                    .hubPanel(cornerRadius: 12)
                }
            }
            .padding(18)
        }
        .background(HubPalette.background)
        .sheet(isPresented: editingTaskPresented) {
            if let task = appState.tasks.first(where: { $0.id == editingTaskID }) {
                TaskInspectorView(task: task)
            }
        }
    }

    private var editingTaskPresented: Binding<Bool> {
        Binding(get: { editingTaskID != nil }, set: { if !$0 { editingTaskID = nil } })
    }

    private func addTask() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.addTask(title: trimmed, course: course, dueDate: Date().addingTimeInterval(3600 * 4))
        title = ""
    }
}

private struct CompactProjectsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var title = ""
    @State private var editingProjectID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HubPageHeader(eyebrow: "Spaces", title: "Projects", subtitle: "Deadlines, tasks, notes, and meetings in one place.")
                HStack {
                    TextField("New project", text: $title).textFieldStyle(.plain).onSubmit(addProject)
                    Button("Create", action: addProject).buttonStyle(HubProminentButtonStyle())
                }
                .padding(14)
                .hubPanel(cornerRadius: 14)

                ForEach(appState.projects.sorted { $0.deadline < $1.deadline }) { project in
                    Button { editingProjectID = project.id } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Circle().fill(project.course.accent).frame(width: 10, height: 10)
                                Text(project.title).font(.system(size: 15, weight: .bold))
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            ProgressView(value: appState.progress(for: project.id)).tint(project.course.accent)
                            HStack {
                                Text(project.course.title)
                                Spacer()
                                Text(project.deadline.formatted(date: .abbreviated, time: .omitted))
                            }
                            .font(.caption)
                            .foregroundStyle(HubPalette.secondaryText)
                        }
                        .padding(14)
                        .hubPanel(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .background(HubPalette.background)
        .sheet(isPresented: editingProjectPresented) {
            if let project = appState.projects.first(where: { $0.id == editingProjectID }) {
                ProjectInspectorView(project: project)
            }
        }
    }

    private var editingProjectPresented: Binding<Bool> {
        Binding(get: { editingProjectID != nil }, set: { if !$0 { editingProjectID = nil } })
    }

    private func addProject() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.addProject(title: trimmed, course: .general, deadline: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
        title = ""
    }
}

private struct CompactNotesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editingNoteID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    HubPageHeader(eyebrow: "Library", title: "Notes", subtitle: "Markdown notes mirrored into your Files-visible folder.")
                    Spacer()
                    Button {
                        let note = appState.addNote()
                        editingNoteID = note.id
                    } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(HubProminentButtonStyle())
                }
                ForEach(appState.notes.sorted { $0.modifiedAt > $1.modifiedAt }) { note in
                    Button { editingNoteID = note.id } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 3).fill(note.course.accent).frame(width: 5, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.title).font(.system(size: 14, weight: .semibold))
                                Text("\(note.folder) • \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(HubPalette.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(13)
                        .hubPanel(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .background(HubPalette.background)
        .sheet(isPresented: editingNotePresented) {
            if let note = appState.notes.first(where: { $0.id == editingNoteID }) {
                CompactNoteEditor(note: note)
            }
        }
    }

    private var editingNotePresented: Binding<Bool> {
        Binding(get: { editingNoteID != nil }, set: { if !$0 { editingNoteID = nil } })
    }
}

private struct CompactNoteEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HubNote
    @State private var showsPreview = true
    @State private var markdownSelection = NSRange(location: 0, length: 0)
    @State private var exportURLs: [URL] = []

    init(note: HubNote) { _draft = State(initialValue: note) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                TextField("Title", text: $draft.title).font(.title2.bold()).textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Folder", text: $draft.folder).textFieldStyle(.roundedBorder)
                    Picker("Course", selection: $draft.course) {
                        ForEach(appState.spaces) { Text($0.title).tag($0) }
                    }
                }
                ObsidianLiveMarkdownEditor(
                    text: $draft.markdown,
                    targetLine: nil,
                    onSelectionChange: { markdownSelection = $0 }
                )
                    .frame(minHeight: 240)
                    .padding(8)
                    .background(HubPalette.grouped)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MarkdownTool.allCases) { tool in
                            Button { insert(tool) } label: { Label(tool.title, systemImage: tool.icon) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                DisclosureGroup("Live Markdown preview", isExpanded: $showsPreview) {
                    MarkdownReadingView(source: draft.markdown, targetLine: nil)
                        .frame(minHeight: 220)
                        .background(HubPalette.grouped)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
            .background(HubPalette.background)
            .navigationTitle("Markdown note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { appState.updateNote(draft); dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Menu("Link task") {
                        ForEach(appState.tasks.filter { !$0.isCompleted }) { task in
                            Button(task.title) { appState.updateNote(draft); appState.toggleLink(noteID: draft.id, taskID: task.id) }
                        }
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        appState.updateNote(draft)
                        exportURLs = appState.exportNote(draft)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !exportURLs.isEmpty {
                    ShareLink(items: exportURLs) {
                        Label("Share PDF, RTF & CSV", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
                }
            }
        }
    }

    private func insert(_ tool: MarkdownTool) {
        let result = tool.applying(to: draft.markdown, selection: markdownSelection)
        draft.markdown = result.text
        markdownSelection = result.selection
    }
}

private struct CompactCalendarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var date = Date()
    @State private var start = 16.0
    @State private var end = 17.0
    @State private var title = "Study block"
    @State private var course: Course = .general
    @State private var taskID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HubPageHeader(eyebrow: "Plan", title: "Calendar", subtitle: "Drag roughly, then type or nudge the exact time.")
                DatePicker("Day", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                CalendarSelectionGrid(date: date, selectionStart: $start, selectionEnd: $end)
                    .frame(minHeight: 620)
                VStack(spacing: 10) {
                    TextField("Block title", text: $title).textFieldStyle(.roundedBorder)
                    Picker("Course", selection: $course) {
                        ForEach(appState.spaces) { Text($0.title).tag($0) }
                    }
                    CalendarTimeFields(date: date, selectionStart: $start, selectionEnd: $end)
                    Button("Add selected time") {
                        appState.addScheduleBlock(title: title, course: course, date: date, startHour: start, duration: max(0.25, end - start))
                    }
                    .buttonStyle(HubProminentButtonStyle())
                }
                .padding(14)
                .hubPanel(cornerRadius: 14)

                VStack(spacing: 10) {
                    Picker("Task to schedule", selection: $taskID) {
                        Text("Choose a task").tag(Optional<UUID>.none)
                        ForEach(appState.tasks.filter { !$0.isCompleted }) { Text($0.title).tag(Optional($0.id)) }
                    }
                    if let taskID {
                        Button("Schedule task at selected time") { appState.schedule(taskID, at: start, on: date) }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(14)
                .hubPanel(cornerRadius: 14)
            }
            .padding(18)
        }
        .background(HubPalette.background)
    }
}

private struct CompactFilesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isImporting = false
    @State private var editingFileID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    HubPageHeader(eyebrow: "Library", title: "Files & PDFs", subtitle: "Import, preview, annotate, and sync study files.")
                    Spacer()
                    Button("Import") { isImporting = true }.buttonStyle(HubProminentButtonStyle())
                }
                ForEach(appState.files) { item in
                    Button { editingFileID = item.id } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.kind == .pdf ? "doc.richtext" : "doc")
                                .font(.title2).foregroundStyle(item.kind == .pdf ? HubPalette.red : item.course.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayName).font(.system(size: 14, weight: .semibold))
                                Text("\(item.kind.rawValue.uppercased()) • \(item.course.title)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(13)
                        .hubPanel(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .background(HubPalette.background)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach(appState.importFile) }
        }
        .sheet(isPresented: editingFilePresented) {
            if let item = appState.files.first(where: { $0.id == editingFileID }) {
                FileInspectorView(item: item).padding(.top)
            }
        }
    }

    private var editingFilePresented: Binding<Bool> {
        Binding(get: { editingFileID != nil }, set: { if !$0 { editingFileID = nil } })
    }
}

private struct CompactJournalView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editingEntryID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    HubPageHeader(eyebrow: "Reflect", title: "Journal", subtitle: "Private daily reflections, saved locally first.")
                    Spacer()
                    Menu {
                        Button("Dated entry", systemImage: "calendar.badge.plus") {
                            editingEntryID = appState.addJournalEntry().id
                        }
                        Button("Undated memo", systemImage: "note.text.badge.plus") {
                            editingEntryID = appState.addJournalMemo().id
                        }
                    } label: { Image(systemName: "plus") }
                        .buttonStyle(HubProminentButtonStyle())
                }
                ForEach(appState.journalEntries.sorted { $0.date > $1.date }) { entry in
                    Button { editingEntryID = entry.id } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title).font(.system(size: 14, weight: .semibold))
                                Text(entry.isDateLinked ? entry.date.formatted(date: .long, time: .omitted) : "Undated memo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(repeating: "●", count: entry.mood)).foregroundStyle(HubPalette.yellow)
                        }
                        .padding(13)
                        .hubPanel(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .background(HubPalette.background)
        .sheet(isPresented: editingEntryPresented) {
            if let entry = appState.journalEntries.first(where: { $0.id == editingEntryID }) {
                CompactJournalEditor(entry: entry)
            }
        }
    }

    private var editingEntryPresented: Binding<Bool> {
        Binding(get: { editingEntryID != nil }, set: { if !$0 { editingEntryID = nil } })
    }
}

private struct CompactJournalEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: JournalEntry

    init(entry: JournalEntry) { _draft = State(initialValue: entry) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Title", text: $draft.title).font(.title2.bold()).textFieldStyle(.roundedBorder)
                Toggle("Linked to date", isOn: $draft.isDateLinked)
                if draft.isDateLinked {
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                }
                Picker("Mood", selection: $draft.mood) {
                    ForEach(1...5, id: \.self) { Text("Mood \($0)").tag($0) }
                }
                TextEditor(text: $draft.body)
                    .padding(8).background(HubPalette.grouped).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
            .background(HubPalette.background)
            .navigationTitle(draft.isDateLinked ? draft.date.formatted(date: .abbreviated, time: .omitted) : "Memo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { appState.updateJournal(draft); dismiss() } }
            }
        }
    }
}

private struct CompactMeetingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editingMeetingID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom) {
                    HubPageHeader(eyebrow: "Projects", title: "Meetings", subtitle: "Capture discussion, summary, and action items.")
                    Spacer()
                    Button {
                        editingMeetingID = appState.addMeeting(title: "New meeting", projectID: appState.selectedProjectID).id
                    } label: { Image(systemName: "plus") }
                    .buttonStyle(HubProminentButtonStyle())
                }
                ForEach(appState.meetings.sorted { $0.date > $1.date }) { meeting in
                    Button { editingMeetingID = meeting.id } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meeting.title).font(.system(size: 14, weight: .semibold))
                                Text(meeting.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !meeting.summary.isEmpty { Image(systemName: "sparkles") }
                            Image(systemName: "chevron.right")
                        }
                        .padding(13)
                        .hubPanel(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
        }
        .background(HubPalette.background)
        .sheet(isPresented: editingMeetingPresented) {
            if let meeting = appState.meetings.first(where: { $0.id == editingMeetingID }) {
                CompactMeetingEditor(meeting: meeting)
            }
        }
    }

    private var editingMeetingPresented: Binding<Bool> {
        Binding(get: { editingMeetingID != nil }, set: { if !$0 { editingMeetingID = nil } })
    }
}

private struct CompactMeetingEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MeetingRecord

    init(meeting: MeetingRecord) { _draft = State(initialValue: meeting) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    TextField("Meeting title", text: $draft.title).font(.title2.bold()).textFieldStyle(.roundedBorder)
                    Picker("Project", selection: $draft.projectID) {
                        Text("No project").tag(Optional<UUID>.none)
                        ForEach(appState.projects) { Text($0.title).tag(Optional($0.id)) }
                    }
                    Text("Transcript / raw notes").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    TextEditor(text: $draft.transcript).frame(minHeight: 220).padding(8).background(HubPalette.grouped).clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("Summary").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    TextEditor(text: $draft.summary).frame(minHeight: 150).padding(8).background(HubPalette.grouped).clipShape(RoundedRectangle(cornerRadius: 12))
                    Button("Generate summary + tasks") {
                        appState.updateMeeting(draft)
                        appState.generateMeetingSummary(draft.id)
                        if let updated = appState.meetings.first(where: { $0.id == draft.id }) { draft = updated }
                    }
                    .buttonStyle(HubProminentButtonStyle())
                }
                .padding()
            }
            .background(HubPalette.background)
            .navigationTitle("Meeting record")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { appState.updateMeeting(draft); dismiss() } }
            }
        }
    }
}

private struct CompactRemindersView: View {
    @EnvironmentObject private var appState: AppState
    @State private var title = ""
    @State private var dueDate = Date().addingTimeInterval(3600)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HubPageHeader(eyebrow: "Remember", title: "Reminders", subtitle: "System notifications for small but important details.")
                VStack(spacing: 10) {
                    TextField("Reminder", text: $title).textFieldStyle(.roundedBorder)
                    DatePicker("When", selection: $dueDate)
                    Button("Add reminder") {
                        appState.addReminder(title: title, dueDate: dueDate)
                        title = ""
                    }
                    .buttonStyle(HubProminentButtonStyle())
                }
                .padding(14).hubPanel(cornerRadius: 14)

                ForEach(appState.reminders.sorted { $0.dueDate < $1.dueDate }) { reminder in
                    HStack(spacing: 12) {
                        Button { appState.toggleReminder(reminder.id) } label: {
                            Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "bell.circle")
                                .font(.title3).foregroundStyle(reminder.isCompleted ? HubPalette.success : HubPalette.yellow)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reminder.title).font(.system(size: 14, weight: .semibold)).strikethrough(reminder.isCompleted)
                            Text(reminder.dueDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(13).hubPanel(cornerRadius: 12)
                }
            }
            .padding(18)
        }
        .background(HubPalette.background)
    }
}

private struct CompactExportView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HubPageHeader(
                    eyebrow: "Output",
                    title: "Export workspace",
                    subtitle: "Create portable CSV and Markdown files for assignments, printing, or archiving."
                )
                Button {
                    appState.exportWorkspace()
                } label: {
                    Label("Export CSV + Markdown", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HubProminentButtonStyle())
                .controlSize(.large)

                if !appState.lastExportURLs.isEmpty {
                    HubSectionTitle(title: "Latest export")
                    ForEach(appState.lastExportURLs, id: \.self) { url in
                        HStack(spacing: 12) {
                            Image(systemName: "doc")
                            Text(url.lastPathComponent)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .accessibilityLabel("Share \(url.lastPathComponent)")
                        }
                        .padding(14)
                        .hubPanel(cornerRadius: 12)
                    }
                }
            }
            .padding(18)
        }
        .background(HubPalette.background)
    }
}

import SwiftUI

/// A dedicated home page for each Space. The Overview tab shows a
/// power-user summary (today's schedule, open tasks, recent notes,
/// active projects) and the segmented filter lets the user drill
/// down to a single category without leaving the Space.
struct SpaceWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: SpaceFilter = .overview
    @State private var newTaskTitle = ""
    @State private var newNoteTitle = ""
    @State private var editingTaskID: UUID?
    @State private var editingNoteID: UUID?
    @State private var editingProjectID: UUID?
    @State private var selectedDate = Date()

    enum SpaceFilter: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case tasks = "Tasks"
        case notes = "Notes"
        case projects = "Projects"
        case files = "Files"
        case schedule = "Schedule"
        var id: String { rawValue }
    }

    private var space: Course? {
        guard let id = appState.selectedSpaceID else { return nil }
        return appState.spaces.first(where: { $0.id == id })
    }

    private var spaceTasks: [HubTask] {
        guard let space else { return [] }
        return appState.tasks.filter { $0.course.id == space.id }
    }

    private var spaceNotes: [HubNote] {
        guard let space else { return [] }
        return appState.notes.filter { $0.course.id == space.id }
    }

    private var spaceProjects: [HubProject] {
        guard let space else { return [] }
        return appState.projects.filter { $0.course.id == space.id && !$0.isArchived }
    }

    private var spaceFiles: [HubFileItem] {
        guard let space else { return [] }
        return appState.files.filter { $0.course.id == space.id }
    }

    private var spaceSchedule: [ScheduleBlock] {
        guard let space else { return [] }
        return appState.scheduleBlocks
            .filter { $0.course.id == space.id }
            .sorted { $0.date < $1.date }
    }

    private var openTaskCount: Int {
        spaceTasks.filter { !$0.isCompleted }.count
    }

    private var overdueTaskCount: Int {
        spaceTasks.filter { $0.isOverdue }.count
    }

    private var dueTodayCount: Int {
        let calendar = Calendar.current
        return spaceTasks.filter { !$0.isCompleted && calendar.isDateInToday($0.dueDate) }.count
    }

    private var todayBlocks: [ScheduleBlock] {
        spaceSchedule.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var weekBlocks: [ScheduleBlock] {
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? Date()
        return spaceSchedule.filter { $0.date >= weekStart && $0.date < weekEnd }
    }

    var body: some View {
        Group {
            if let space {
                content(for: space)
            } else {
                HubEmptyState(
                    icon: "rectangle.3.group.fill",
                    title: "Pick a Space",
                    message: "Select a Space from the sidebar to see its home page."
                )
            }
        }
        .background(HubPalette.background)
        .sheet(item: editingTaskBinding) { task in
            TaskInspectorSheet(taskID: task.id)
        }
        .sheet(item: editingNoteBinding) { note in
            NoteInspectorSheet(noteID: note.id)
        }
        .sheet(item: editingProjectBinding) { project in
            ProjectInspectorSheet(projectID: project.id)
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private func content(for space: Course) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(for: space)
            filterBar

            ScrollView {
                Group {
                    switch filter {
                    case .overview: overviewBody(space: space)
                    case .tasks: tasksBody(space: space)
                    case .notes: notesBody(space: space)
                    case .projects: projectsBody(space: space)
                    case .files: filesBody(space: space)
                    case .schedule: scheduleBody(space: space)
                    }
                }
                .padding(24)
            }
        }
    }

    // MARK: - Header

    private func header(for space: Course) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(space.accent)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(String(space.title.prefix(1)).uppercased())
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(space.title)
                        .font(.system(size: 30, weight: .bold))
                    Text("\(openTaskCount) open tasks · \(spaceNotes.count) notes · \(spaceProjects.count) projects")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    let task = appState.addTask(title: "New task", course: space)
                    editingTaskID = task.id
                } label: { Label("Task", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                Button {
                    let note = appState.addNote(title: "New note", course: space)
                    editingNoteID = note.id
                } label: { Label("Note", systemImage: "doc.text") }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        Picker("View", selection: $filter) {
            ForEach(SpaceFilter.allCases) { f in
                Text(f.rawValue).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    // MARK: - Overview

    @ViewBuilder
    private func overviewBody(space: Course) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            statGrid(space: space)

            if !todayBlocks.isEmpty {
                todayScheduleCard
            }

            HStack(alignment: .top, spacing: 16) {
                openTasksCard(space: space, limit: 6)
                recentNotesCard(space: space, limit: 5)
            }

            if !spaceProjects.isEmpty {
                activeProjectsCard(space: space)
            }
        }
    }

    private func statGrid(space: Course) -> some View {
        HStack(spacing: 12) {
            statCard(label: "Open tasks", value: "\(openTaskCount)", tint: space.accent)
            statCard(label: "Due today", value: "\(dueTodayCount)", tint: HubPalette.yellow)
            statCard(label: "Overdue", value: "\(overdueTaskCount)", tint: HubPalette.red)
            statCard(label: "Notes", value: "\(spaceNotes.count)", tint: HubPalette.hubAccent)
            statCard(label: "Projects", value: "\(spaceProjects.count)", tint: .purple)
            statCard(label: "Files", value: "\(spaceFiles.count)", tint: HubPalette.success)
        }
    }

    private func statCard(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .monospacedDigit()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HubPalette.grouped)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HubPalette.separator, lineWidth: 0.5)
        )
    }

    private var todayScheduleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HubSectionTitle(title: "Today · Schedule", trailing: "\(todayBlocks.count)")
                Spacer()
                Button("Open calendar") { appState.navigate(to: .calendar) }
                    .buttonStyle(.borderless)
            }
            VStack(spacing: 0) {
                ForEach(todayBlocks) { block in
                    HubScheduleRow(block: block)
                    if block.id != todayBlocks.last?.id { Divider() }
                }
            }
            .background(HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HubPalette.separator, lineWidth: 0.5)
            )
        }
    }

    private func openTasksCard(space: Course, limit: Int) -> some View {
        let openTasks = spaceTasks.filter { !$0.isCompleted }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(limit)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HubSectionTitle(title: "Open tasks", trailing: "\(openTaskCount)")
                Spacer()
                Button("See all") { filter = .tasks }
                    .buttonStyle(.borderless)
            }
            VStack(spacing: 0) {
                if openTasks.isEmpty {
                    Text("No open tasks — capture one above.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(20)
                } else {
                    ForEach(Array(openTasks)) { task in
                        Button { editingTaskID = task.id } label: {
                            HubTaskRow(task: task)
                        }
                        .buttonStyle(.plain)
                        if task.id != openTasks.last?.id { Divider() }
                    }
                }
            }
            .background(HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HubPalette.separator, lineWidth: 0.5)
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func recentNotesCard(space: Course, limit: Int) -> some View {
        let recent = spaceNotes.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(limit)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HubSectionTitle(title: "Recent notes", trailing: "\(spaceNotes.count)")
                Spacer()
                Button("See all") { filter = .notes }
                    .buttonStyle(.borderless)
            }
            VStack(spacing: 0) {
                if recent.isEmpty {
                    Text("No notes yet — write your first one above.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(20)
                } else {
                    ForEach(Array(recent)) { note in
                        Button { editingNoteID = note.id } label: {
                            HubNoteRow(note: note)
                        }
                        .buttonStyle(.plain)
                        if note.id != recent.last?.id { Divider() }
                    }
                }
            }
            .background(HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HubPalette.separator, lineWidth: 0.5)
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func activeProjectsCard(space: Course) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HubSectionTitle(title: "Active projects", trailing: "\(spaceProjects.count)")
            VStack(spacing: 8) {
                ForEach(spaceProjects.sorted { $0.deadline < $1.deadline }) { project in
                    Button { editingProjectID = project.id } label: {
                        projectRow(project)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func projectRow(_ project: HubProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(project.course.accent).frame(width: 8, height: 8)
                Text(project.title).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("Due \(project.deadline.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: appState.progress(for: project.id))
                .progressViewStyle(.linear)
                .tint(project.course.accent)
        }
        .padding(12)
        .background(HubPalette.grouped)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(HubPalette.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Tasks tab

    @ViewBuilder
    private func tasksBody(space: Course) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Add a task for \(space.title)", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTask(in: space) }
                Button("Add", action: { addTask(in: space) })
                    .buttonStyle(HubProminentButtonStyle())
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.bottom, 4)

            VStack(spacing: 0) {
                let open = spaceTasks.filter { !$0.isCompleted }.sorted { $0.dueDate < $1.dueDate }
                if open.isEmpty {
                    Text("No open tasks in \(space.title).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(20)
                } else {
                    ForEach(open) { task in
                        Button { editingTaskID = task.id } label: {
                            HubTaskRow(task: task)
                        }
                        .buttonStyle(.plain)
                        if task.id != open.last?.id { Divider() }
                    }
                }
            }
            .background(HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HubPalette.separator, lineWidth: 0.5)
            )

            let done = spaceTasks.filter { $0.isCompleted }.sorted { $0.dueDate > $1.dueDate }
            if !done.isEmpty {
                HubSectionTitle(title: "Recently completed", trailing: "\(done.count)")
                VStack(spacing: 0) {
                    ForEach(done.prefix(5)) { task in
                        HubTaskRow(task: task)
                            .opacity(0.6)
                        if task.id != done.prefix(5).last?.id { Divider() }
                    }
                }
                .background(HubPalette.grouped)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(HubPalette.separator, lineWidth: 0.5)
                )
            }
        }
    }

    private func addTask(in space: Course) {
        let trimmed = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = appState.addTask(title: trimmed, course: space, dueDate: Date().addingTimeInterval(4 * 3600))
        newTaskTitle = ""
    }

    // MARK: - Notes tab

    @ViewBuilder
    private func notesBody(space: Course) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Add a note for \(space.title)", text: $newNoteTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addNote(in: space) }
                Button("Add", action: { addNote(in: space) })
                    .buttonStyle(HubProminentButtonStyle())
                    .disabled(newNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            VStack(spacing: 0) {
                if spaceNotes.isEmpty {
                    Text("No notes in \(space.title) yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(20)
                } else {
                    let sortedNotes = spaceNotes.sorted { $0.modifiedAt > $1.modifiedAt }
                    ForEach(sortedNotes) { note in
                        Button { editingNoteID = note.id } label: {
                            HubNoteRow(note: note)
                        }
                        .buttonStyle(.plain)
                        if note.id != sortedNotes.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .background(HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HubPalette.separator, lineWidth: 0.5)
            )
        }
    }

    private func addNote(in space: Course) {
        let trimmed = newNoteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = appState.addNote(title: trimmed, course: space)
        editingNoteID = note.id
        newNoteTitle = ""
    }

    // MARK: - Projects tab

    @ViewBuilder
    private func projectsBody(space: Course) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    let project = appState.addProject(
                        title: "New project",
                        course: space,
                        deadline: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                    )
                    editingProjectID = project.id
                } label: { Label("New project", systemImage: "plus") }
                    .buttonStyle(HubProminentButtonStyle())

                Spacer()
            }
            if spaceProjects.isEmpty {
                HubEmptyState(icon: "folder", title: "No projects yet", message: "Start a project to track related tasks and notes.")
            } else {
                VStack(spacing: 10) {
                    ForEach(spaceProjects.sorted { $0.deadline < $1.deadline }) { project in
                        Button { editingProjectID = project.id } label: {
                            projectRow(project)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Files tab

    @ViewBuilder
    private func filesBody(space: Course) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if spaceFiles.isEmpty {
                HubEmptyState(icon: "doc", title: "No files yet", message: "Import PDFs and study files to attach them to this Space.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(spaceFiles) { file in
                        fileCard(file)
                    }
                }
            }
        }
    }

    private func fileCard(_ file: HubFileItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: file.kind == .pdf ? "doc.richtext" : "doc")
                .font(.title2)
                .foregroundStyle(file.kind == .pdf ? HubPalette.red : HubPalette.hubAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(file.kind.rawValue.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(HubPalette.grouped)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HubPalette.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Schedule tab

    @ViewBuilder
    private func scheduleBody(space: Course) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if spaceSchedule.isEmpty {
                HubEmptyState(icon: "calendar", title: "No schedule yet", message: "Drop a task onto the calendar or add a study block in this Space.")
            } else {
                ForEach(weekBlocks, id: \.id) { block in
                    HubScheduleRow(block: block)
                }
            }
        }
    }

    // MARK: - Bindings

    private var editingTaskBinding: Binding<SpaceIdentifiableTask?> {
        Binding(
            get: { editingTaskID.map(SpaceIdentifiableTask.init(id:)) },
            set: { editingTaskID = $0?.id }
        )
    }
    private var editingNoteBinding: Binding<SpaceIdentifiableNote?> {
        Binding(
            get: { editingNoteID.map(SpaceIdentifiableNote.init(id:)) },
            set: { editingNoteID = $0?.id }
        )
    }
    private var editingProjectBinding: Binding<SpaceIdentifiableProject?> {
        Binding(
            get: { editingProjectID.map(SpaceIdentifiableProject.init(id:)) },
            set: { editingProjectID = $0?.id }
        )
    }
}

// MARK: - Reusable row components

struct HubTaskRow: View {
    @EnvironmentObject private var appState: AppState
    let task: HubTask

    var body: some View {
        HStack(spacing: 12) {
            Button { appState.toggleComplete(task.id) } label: {
                Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? HubPalette.success : task.course.accent)
            }
            .buttonStyle(.plain)
            Rectangle()
                .fill(task.course.accent)
                .frame(width: 3, height: 32)
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(task.course.title) · \(formattedDue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(task.dueTimeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
    }

    private var formattedDue: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(task.dueDate) { return "Today" }
        if calendar.isDateInYesterday(task.dueDate) { return "Yesterday" }
        if calendar.isDateInTomorrow(task.dueDate) { return "Tomorrow" }
        return task.dueDate.formatted(date: .abbreviated, time: .omitted)
    }
}

struct HubNoteRow: View {
    let note: HubNote

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(note.course.accent)
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(note.folder) · \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
    }
}

struct HubScheduleRow: View {
    let block: ScheduleBlock

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(block.startHour))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(block.startHour < 12 ? "AM" : "PM")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 36)
            RoundedRectangle(cornerRadius: 2)
                .fill(block.course.accent)
                .frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.system(size: 14, weight: .semibold))
                Text("\(block.course.title) · \(block.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }
}

private struct SpaceIdentifiableTask: Identifiable {
    let id: UUID
}
private struct SpaceIdentifiableNote: Identifiable {
    let id: UUID
}
private struct SpaceIdentifiableProject: Identifiable {
    let id: UUID
}

// MARK: - Inspector sheets (reused from iPhone)

struct TaskInspectorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID
    @State private var draft: HubTask?

    private var task: HubTask? { appState.tasks.first(where: { $0.id == taskID }) }

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    Form {
                        Section("Title") { TextField("Task title", text: Binding(get: { draft.title }, set: { v in var d = draft; d.title = v; self.draft = d })) }
                        Section("Space") {
                            Picker("Space", selection: Binding(get: { draft.course }, set: { v in var d = draft; d.course = v; self.draft = d })) {
                                ForEach(appState.spaces) { Text($0.title).tag($0) }
                            }
                        }
                        Section("Due") {
                            DatePicker("Due", selection: Binding(get: { draft.dueDate }, set: { v in var d = draft; d.dueDate = v; self.draft = d }), displayedComponents: [.date, .hourAndMinute])
                        }
                        Section("Details") {
                            TextField("Notes", text: Binding(get: { draft.details }, set: { v in var d = draft; d.details = v; self.draft = d }), axis: .vertical)
                                .lineLimit(3...8)
                        }
                    }
                } else {
                    HubEmptyState(icon: "exclamationmark.triangle", title: "Task not found", message: "It may have been deleted.")
                }
            }
            .navigationTitle("Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if let draft { appState.updateTask(draft) }; dismiss() }
                        .disabled(draft == nil)
                }
            }
            .onAppear { if draft == nil { draft = task } }
        }
        .frame(minWidth: 480, minHeight: 480)
    }
}

struct NoteInspectorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let noteID: UUID
    @State private var draft: HubNote?

    private var note: HubNote? { appState.notes.first(where: { $0.id == noteID }) }

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    Form {
                        Section("Title") {
                            TextField("Title", text: Binding(get: { draft.title }, set: { v in var d = draft; d.title = v; self.draft = d }))
                                .font(.system(size: 17, weight: .semibold))
                        }
                        Section("Folder") {
                            TextField("Folder", text: Binding(get: { draft.folder }, set: { v in var d = draft; d.folder = v; self.draft = d }))
                            Picker("Space", selection: Binding(get: { draft.course }, set: { v in var d = draft; d.course = v; self.draft = d })) {
                                ForEach(appState.spaces) { Text($0.title).tag($0) }
                            }
                        }
                        Section("Markdown") {
                            TextEditor(text: Binding(get: { draft.markdown }, set: { v in var d = draft; d.markdown = v; self.draft = d }))
                                .font(.system(size: 14, design: .monospaced))
                                .frame(minHeight: 220)
                        }
                    }
                } else {
                    HubEmptyState(icon: "doc.text", title: "Note not found", message: "It may have been removed.")
                }
            }
            .navigationTitle("Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if let draft { appState.updateNote(draft) }; dismiss() }
                        .disabled(draft == nil)
                }
            }
            .onAppear { if draft == nil { draft = note } }
        }
        .frame(minWidth: 540, minHeight: 520)
    }
}

struct ProjectInspectorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let projectID: UUID
    @State private var draft: HubProject?

    private var project: HubProject? { appState.projects.first(where: { $0.id == projectID }) }

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    Form {
                        Section("Title") {
                            TextField("Project title", text: Binding(get: { draft.title }, set: { v in var d = draft; d.title = v; self.draft = d }))
                        }
                        Section("Space") {
                            Picker("Space", selection: Binding(get: { draft.course }, set: { v in var d = draft; d.course = v; self.draft = d })) {
                                ForEach(appState.spaces) { Text($0.title).tag($0) }
                            }
                        }
                        Section("Deadline") {
                            DatePicker("Deadline", selection: Binding(get: { draft.deadline }, set: { v in var d = draft; d.deadline = v; self.draft = d }), displayedComponents: [.date])
                        }
                        Section("Details") {
                            TextField("Notes", text: Binding(get: { draft.details }, set: { v in var d = draft; d.details = v; self.draft = d }), axis: .vertical)
                                .lineLimit(3...8)
                        }
                    }
                } else {
                    HubEmptyState(icon: "exclamationmark.triangle", title: "Project not found", message: "It may have been deleted.")
                }
            }
            .navigationTitle("Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if let draft { appState.updateProject(draft) }; dismiss() }
                        .disabled(draft == nil)
                }
            }
            .onAppear { if draft == nil { draft = project } }
        }
        .frame(minWidth: 500, minHeight: 480)
    }
}

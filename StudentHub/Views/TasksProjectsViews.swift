import SwiftUI

enum TaskListMode {
    case inbox
    case all
}

struct TasksWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    let mode: TaskListMode
    @State private var newTitle = ""
    @State private var newCourse: Course = .general
    @State private var newDueDate = Date()
    @State private var newEstimatedMinutes: Int? = 30
    @State private var newRecurrence: RecurrenceRule?
    @State private var showsCompleted = false

    private var visibleTasks: [HubTask] {
        appState.tasks
            .filter { task in
                let modeMatches = mode == .all || (task.projectID == nil && task.parentTaskID == nil)
                let courseMatches = appState.taskCourseFilter == nil || task.course == appState.taskCourseFilter
                return modeMatches && courseMatches && (showsCompleted || !task.isCompleted)
            }
            .sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    HubPageHeader(
                        eyebrow: mode == .all ? "Plan" : "Capture",
                        title: mode == .all ? (appState.taskCourseFilter?.title ?? "All tasks") : "Inbox",
                        subtitle: mode == .all ? (appState.taskCourseFilter == nil ? "Every assignment, personal task, and subtask." : "Tasks filtered to this course.") : "Unsorted work that still needs a home."
                    )
                    Spacer()
                    Toggle("Completed", isOn: $showsCompleted)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                newTaskComposer

                if visibleTasks.isEmpty {
                    HubEmptyState(
                        icon: "checkmark.circle",
                        title: "Nothing waiting",
                        message: "Add a task above or capture one from Command Hub."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(visibleTasks) { task in
                                TaskWorkspaceRow(task: task)
                            }
                        }
                        .padding(.bottom, 22)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let selectedID = appState.selectedTaskID,
               let selectedTask = appState.tasks.first(where: { $0.id == selectedID }) {
                Divider()
                TaskInspectorView(task: selectedTask)
                    .id(selectedTask.id)
                    .frame(width: 330)
            }
        }
        .background(HubPalette.background)
        .onAppear {
            if !appState.spaces.contains(newCourse) { newCourse = appState.defaultSpace }
        }
    }

    private var newTaskComposer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(HubPalette.hubAccent)
                TextField("Add an assignment or task", text: $newTitle)
                    .textFieldStyle(.plain)
                    .onSubmit(addTask)
                Button("Add", action: addTask)
                    .buttonStyle(HubProminentButtonStyle())
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Divider()
            HStack(spacing: 10) {
                Picker("Course", selection: $newCourse) {
                    ForEach(appState.spaces) { course in Text(course.title).tag(course) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                Picker("Predicted time", selection: $newEstimatedMinutes) {
                    Text("No estimate").tag(Optional<Int>.none)
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                        Text(minutes.studyDurationLabel).tag(Optional(minutes))
                    }
                }
                .labelsHidden()
                .frame(width: 104)
                HubRecurrencePicker(selection: $newRecurrence)
                    .labelsHidden()
                    .frame(width: 124)
            }
            DatePicker("Due", selection: $newDueDate)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(14)
        .hubPanel(cornerRadius: 16)
    }

    private func addTask() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = appState.addTask(
            title: trimmed,
            course: newCourse,
            dueDate: newDueDate,
            estimatedMinutes: newEstimatedMinutes,
            recurrence: newRecurrence
        )
        appState.selectedTaskID = task.id
        newTitle = ""
        newRecurrence = nil
    }
}

struct TaskWorkspaceRow: View {
    @EnvironmentObject private var appState: AppState
    let task: HubTask

    private var projectName: String? {
        guard let projectID = task.projectID else { return nil }
        return appState.projects.first(where: { $0.id == projectID })?.title
    }

    var body: some View {
        Button {
            appState.selectedTaskID = task.id
        } label: {
            HStack(spacing: 12) {
                Button {
                    appState.toggleComplete(task.id)
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(task.isCompleted ? HubPalette.success : task.course.accent)
                }
                .buttonStyle(.plain)

                Circle()
                    .fill(task.course.accent)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .semibold))
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? HubPalette.secondaryText : HubPalette.primaryText)
                    HStack(spacing: 7) {
                        Text(task.course.title)
                        if let projectName {
                            Text("•")
                            Text(projectName)
                        }
                        if task.parentTaskID != nil {
                            Text("• subtask")
                        }
                        if let estimate = task.estimatedDurationLabel {
                            Text("• \(estimate)")
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HubPalette.secondaryText)
                }
                Spacer()
                if task.linkedNoteID != nil {
                    Image(systemName: "note.text")
                        .foregroundStyle(HubPalette.secondaryText)
                }
                if let recurrence = task.recurrence {
                    Image(systemName: "repeat")
                        .foregroundStyle(HubPalette.secondaryText)
                        .help(recurrence.title)
                }
                Text(task.dueDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(task.dueDate < Date() && !task.isCompleted ? HubPalette.red : HubPalette.secondaryText)
            }
            .padding(12)
            .background(appState.selectedTaskID == task.id ? HubPalette.selected : HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(HubPalette.separator.opacity(0.75), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(task.isCompleted ? "Mark incomplete" : "Complete") { appState.toggleComplete(task.id) }
            Button("Schedule on calendar") {
                let components = Calendar.current.dateComponents([.hour, .minute], from: task.dueDate)
                let hour = Double(components.hour ?? 16) + Double(components.minute ?? 0) / 60
                appState.schedule(task.id, at: max(0, hour - 1), on: task.dueDate)
            }
            Divider()
            Button("Delete", role: .destructive) { appState.deleteTask(task.id) }
        }
    }
}

struct TaskInspectorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft: HubTask
    @State private var subtaskTitle = ""

    init(task: HubTask) {
        _draft = State(initialValue: task)
    }

    private var subtasks: [HubTask] {
        appState.tasks.filter { $0.parentTaskID == draft.id }.sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Task details")
                        .font(.system(size: 17, weight: .bold))
                    Spacer()
                    Button { appState.selectedTaskID = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                }

                TextField("Task title", text: $draft.title, axis: .vertical)
                    .font(.system(size: 18, weight: .semibold))
                    .textFieldStyle(.plain)

                field("Course") {
                    Picker("Course", selection: $draft.course) {
                        ForEach(appState.spaces) { course in Text(course.title).tag(course) }
                    }
                    .labelsHidden()
                }
                field("Due") {
                    DatePicker("", selection: $draft.dueDate)
                        .labelsHidden()
                }
                field("Repeat") {
                    HubRecurrencePicker(selection: $draft.recurrence)
                        .labelsHidden()
                }
                field("Predicted time") {
                    Picker("Predicted time", selection: $draft.estimatedMinutes) {
                        Text("Not estimated").tag(Optional<Int>.none)
                        ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                            Text(minutes.studyDurationLabel).tag(Optional(minutes))
                        }
                    }
                    .labelsHidden()
                }
                field("Project") {
                    Picker("Project", selection: $draft.projectID) {
                        Text("No project").tag(Optional<UUID>.none)
                        ForEach(appState.projects) { project in
                            Text(project.title).tag(Optional(project.id))
                        }
                    }
                    .labelsHidden()
                }
                field("Linked note") {
                    Picker("Note", selection: $draft.linkedNoteID) {
                        Text("No note").tag(Optional<UUID>.none)
                        ForEach(appState.notes) { note in
                            Text(note.title).tag(Optional(note.id))
                        }
                    }
                    .labelsHidden()
                }
                field("Details") {
                    TextEditor(text: $draft.details)
                        .font(.system(size: 12))
                        .frame(minHeight: 90)
                        .padding(6)
                        .background(HubPalette.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack {
                    Button("Save") {
                        appState.updateTask(draft)
                    }
                    .buttonStyle(HubProminentButtonStyle())
                    Button("Schedule") {
                        appState.updateTask(draft)
                        let components = Calendar.current.dateComponents([.hour, .minute], from: draft.dueDate)
                        let hour = Double(components.hour ?? 16) + Double(components.minute ?? 0) / 60
                        appState.schedule(draft.id, at: max(0, hour - 1), on: draft.dueDate)
                    }
                    .buttonStyle(.bordered)
                }

                Divider()
                HubSectionTitle(title: "Subtasks", trailing: "\(subtasks.filter(\.isCompleted).count)/\(subtasks.count)")
                HStack {
                    TextField("Add subtask", text: $subtaskTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addSubtask)
                    Button(action: addSubtask) { Image(systemName: "plus") }
                        .disabled(subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ForEach(subtasks) { task in
                    HStack {
                        Button { appState.toggleComplete(task.id) } label: {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.plain)
                        Text(task.title)
                            .font(.system(size: 12))
                            .strikethrough(task.isCompleted)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Delete subtask", role: .destructive) {
                            appState.deleteTask(task.id)
                        }
                    }
                }

                Divider()
                Button("Delete task", role: .destructive) {
                    appState.deleteTask(draft.id)
                }
            }
            .padding(20)
        }
        .background(HubPalette.sidebar)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(HubPalette.secondaryText)
            content()
        }
    }

    private func addSubtask() {
        let title = subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        appState.addTask(title: title, course: draft.course, dueDate: draft.dueDate, projectID: draft.projectID, parentTaskID: draft.id)
        subtaskTitle = ""
    }
}

struct ProjectsWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var newProjectName = ""
    @State private var newProjectCourseID = Course.general.id
    @State private var newProjectDeadline = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HubPageHeader(eyebrow: "Spaces", title: "Projects", subtitle: "Keep deadlines, notes, meetings, and subtasks together.")
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                            .foregroundStyle(selectedProjectCourse.accent)
                        TextField("Project name", text: $newProjectName)
                            .textFieldStyle(.plain)
                            .onSubmit(addProject)
                        Button("Create project", action: addProject)
                            .buttonStyle(HubProminentButtonStyle())
                            .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Divider()
                    VStack(spacing: 8) {
                        HStack {
                            Text("Space")
                                .foregroundStyle(HubPalette.secondaryText)
                            Spacer()
                            Picker("", selection: $newProjectCourseID) {
                                ForEach(appState.spaces) { course in Text(course.title).tag(course.id) }
                            }
                            .labelsHidden()
                            .frame(minWidth: 120, maxWidth: 180)
                        }
                        HStack {
                            Text("Deadline")
                                .foregroundStyle(HubPalette.secondaryText)
                            Spacer()
                            DatePicker("", selection: $newProjectDeadline, displayedComponents: [.date])
                                .labelsHidden()
                                .fixedSize()
                        }
                    }
                    .font(.callout)
                }
                .padding(14)
                .hubPanel(cornerRadius: 14)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(appState.projects.sorted { $0.deadline < $1.deadline }) { project in
                            projectRow(project)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if let projectID = appState.selectedProjectID,
               let project = appState.projects.first(where: { $0.id == projectID }) {
                Divider()
                ProjectInspectorView(project: project)
                    .id(project.id)
                    .frame(width: 370)
            }
        }
        .background(HubPalette.background)
        .onAppear {
            if !appState.spaces.contains(where: { $0.id == newProjectCourseID }) {
                newProjectCourseID = appState.defaultSpace.id
            }
        }
    }

    private func projectRow(_ project: HubProject) -> some View {
        let progress = appState.progress(for: project.id)
        return Button {
            appState.selectedProjectID = project.id
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    RoundedRectangle(cornerRadius: 3).fill(project.course.accent).frame(width: 10, height: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.title).font(.system(size: 15, weight: .bold))
                        Text(project.course.title).font(.system(size: 10, weight: .medium)).foregroundStyle(HubPalette.secondaryText)
                    }
                    Spacer()
                    Text(project.deadline.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(project.deadline < Date() ? HubPalette.red : HubPalette.secondaryText)
                }
                ProgressView(value: progress)
                    .tint(project.course.accent)
                HStack {
                    Text("\(Int(progress * 100))% complete")
                    Spacer()
                    Text("\(appState.tasks.filter { $0.projectID == project.id }.count) tasks")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(HubPalette.secondaryText)
            }
            .padding(14)
            .background(appState.selectedProjectID == project.id ? HubPalette.selected : HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).stroke(HubPalette.separator, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func addProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let project: HubProject = withAnimation(.easeOut(duration: 0.18)) {
            appState.addProject(title: name, course: selectedProjectCourse, deadline: newProjectDeadline)
        }
        appState.statusMessage = "Created project \(project.title)"
        newProjectName = ""
        newProjectDeadline = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }

    private var selectedProjectCourse: Course {
        appState.spaces.first(where: { $0.id == newProjectCourseID }) ?? appState.defaultSpace
    }
}

struct ProjectInspectorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft: HubProject
    @State private var taskTitle = ""

    init(project: HubProject) {
        _draft = State(initialValue: project)
    }

    private var tasks: [HubTask] {
        appState.tasks.filter { $0.projectID == draft.id && $0.parentTaskID == nil }.sorted { $0.dueDate < $1.dueDate }
    }

    private var meetings: [MeetingRecord] {
        appState.meetings.filter { $0.projectID == draft.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Project details").font(.system(size: 17, weight: .bold))
                    Spacer()
                    Button { appState.selectedProjectID = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                TextField("Project name", text: $draft.title)
                    .font(.system(size: 19, weight: .bold))
                    .textFieldStyle(.plain)
                Picker("Course", selection: $draft.course) {
                    ForEach(appState.spaces) { course in Text(course.title).tag(course) }
                }
                DatePicker("Deadline", selection: $draft.deadline)
                TextEditor(text: $draft.details)
                    .frame(minHeight: 90)
                    .padding(6)
                    .background(HubPalette.background)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button("Save project") { appState.updateProject(draft) }
                    .buttonStyle(HubProminentButtonStyle())

                Divider()
                HubSectionTitle(title: "Tasks", trailing: "\(tasks.filter(\.isCompleted).count)/\(tasks.count)")
                HStack {
                    TextField("Add project task", text: $taskTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTask)
                    Button(action: addTask) { Image(systemName: "plus") }
                }
                ForEach(tasks) { task in
                    HStack {
                        Button { appState.toggleComplete(task.id) } label: {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.plain)
                        Button(task.title) {
                            appState.selectedTaskID = task.id
                            appState.navigate(to: .tasks)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .font(.system(size: 12))
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Delete task", role: .destructive) {
                            appState.deleteTask(task.id)
                        }
                    }
                }

                Divider()
                HubSectionTitle(title: "Meeting records", trailing: "\(meetings.count)")
                ForEach(meetings) { meeting in
                    Button(meeting.title) {
                        appState.selectedMeetingID = meeting.id
                        appState.navigate(to: .meetings)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                }
                Button("Add meeting") {
                    appState.addMeeting(title: "New project meeting", projectID: draft.id)
                    appState.navigate(to: .meetings)
                }
                .buttonStyle(.bordered)

                Divider()
                Button("Delete project", role: .destructive) { appState.deleteProject(draft.id) }
            }
            .padding(20)
        }
        .background(HubPalette.sidebar)
    }

    private func addTask() {
        let title = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        appState.addTask(title: title, course: draft.course, dueDate: draft.deadline, projectID: draft.id)
        taskTitle = ""
    }
}

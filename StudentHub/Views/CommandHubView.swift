import SwiftUI

struct CommandHubView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case today = "Today"
        case all = "All"
        case search = "Search"

        var id: String { rawValue }
    }

    @EnvironmentObject private var appState: AppState
    @State private var scope: Scope = .today
    @State private var command = ""
    let onClose: () -> Void

    private let hints = [
        CommandHint(command: "add Chem lab report tomorrow 7:30 pm", detail: "Create a dated task", icon: "calendar.badge.plus"),
        CommandHint(command: "move Court case prep to Friday 4 pm", detail: "Find and reschedule a task", icon: "arrow.right.circle"),
        CommandHint(command: "/capture Ask Ms. Li about sources", detail: "Save an unprocessed thought", icon: "square.and.pencil"),
        CommandHint(command: "/notes", detail: "Open the notes workspace", icon: "doc.text")
    ]

    private var filteredTasks: [HubTask] {
        let base = scope == .today
            ? appState.tasks.filter { Calendar.current.isDateInToday($0.dueDate) }
            : appState.tasks
        guard scope == .search else { return base }
        var query = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.hasPrefix("search ") { query = String(query.dropFirst(7)) }
        if query.hasPrefix("find ") { query = String(query.dropFirst(5)) }
        guard !query.isEmpty, !query.hasPrefix("/") else { return base }
        return base.filter {
            $0.title.lowercased().contains(query) ||
            $0.course.title.lowercased().contains(query) ||
            $0.details.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            commandField

            ScrollView {
                commandGuidance
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                VStack(spacing: 0) {
                    HStack {
                        Text(scope.rawValue)
                            .font(.headline)
                        Text("· \(filteredTasks.count) tasks")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(16)

                    Divider()

                    ForEach(filteredTasks) { task in
                        TaskRow(task: task)
                            .contentShape(Rectangle())
                            .onTapGesture { appState.select(task) }
                            .draggable(task.id.uuidString)

                        if appState.selectedTaskID == task.id {
                            TaskDetail(task: task)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if task.id != filteredTasks.last?.id {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
                .hubPanel()
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("SCRATCHPAD")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("/capture anything")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    if appState.captures.isEmpty {
                        Text("Quick captures will wait here until you turn them into tasks or notes.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.captures.prefix(5)) { capture in
                            CaptureRow(capture: capture)
                        }
                    }
                }
                .padding(14)
                .hubPanel()
                .padding(16)
            }

            keyboardHints
        }
        .background(Color.hubBackground)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Command Hub")
                .font(.title2.bold())
            Spacer()
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 230)

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close Command Hub")
        }
        .padding(16)
    }

    private var commandField: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
            TextField("Try “add essay next Friday 4 pm” or type /", text: $command)
                .font(.title3)
                .textFieldStyle(.plain)
                .onSubmit { applyCommand() }
            if !command.isEmpty {
                Button { command = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Button("Run") { applyCommand() }
                .buttonStyle(HubProminentButtonStyle())
        }
        .padding(14)
        .hubPanel(cornerRadius: 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var commandGuidance: some View {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("/") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(trimmed.hasPrefix("/") ? "Commands" : "Try a command", systemImage: "lightbulb")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("Try Jul 22, 7/22, in 3 days, 下周三, or 7月20日")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                ForEach(filteredHints(for: trimmed)) { hint in
                    Button {
                        command = hint.command
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: hint.icon)
                                .frame(width: 18)
                                .foregroundStyle(HubPalette.hubAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hint.command).font(.system(size: 11, weight: .semibold, design: .monospaced))
                                Text(hint.detail).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.left").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 42)
                        .background(HubPalette.selected.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .hubPanel(cornerRadius: 12)
        } else {
            let interpretation = CommandInterpreter.interpret(trimmed, spaces: appState.spaces)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(interpretation.summary, systemImage: intentIcon(interpretation.intent))
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("Press ↵ to run").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(interpretation.draft.recognizedTokens) { token in
                        Label(token.text, systemImage: token.icon)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .frame(height: 25)
                            .background(HubPalette.selected)
                            .clipShape(Capsule())
                    }
                    if interpretation.draft.recognizedTokens.isEmpty {
                        Text("No date found — defaults to today at 7:30 pm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if case .rescheduleTask(let query) = interpretation.intent {
                    let match = appState.tasks.first { $0.title.localizedCaseInsensitiveContains(query) }
                    Text(match == nil ? "No existing task matches “\(query)” yet." : "Matched: \(match!.title) → \(interpretation.draft.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(match == nil ? HubPalette.red : HubPalette.secondaryText)
                } else {
                    Text("Due \(interpretation.draft.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(HubPalette.secondaryText)
                }
            }
            .padding(12)
            .hubPanel(cornerRadius: 12)
        }
    }

    private var keyboardHints: some View {
        HStack(spacing: 22) {
            Label("Navigate", systemImage: "arrow.up.arrow.down")
            Label("Open", systemImage: "return")
            Label("Actions", systemImage: "command")
            Spacer()
            Text("⇧⌘K Toggle")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(16)
        .overlay(alignment: .top) { Divider() }
    }

    private func applyCommand() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "/today": scope = .today
        case "/all", "/tasks":
            scope = .all
            if trimmed.lowercased() == "/tasks" { appState.navigate(to: .tasks) }
        case "/calendar": appState.navigate(to: .calendar)
        case "/projects": appState.navigate(to: .projects)
        case "/notes": appState.navigate(to: .notes)
        case "/files": appState.navigate(to: .files)
        case "/meetings": appState.navigate(to: .meetings)
        case "/reminders": appState.navigate(to: .reminders)
        case "/pomo", "/pomodoro": appState.navigate(to: .pomodoro)
        case "/export": appState.navigate(to: .export)
        default:
            if trimmed.lowercased().hasPrefix("/capture ") {
                appState.addCapture(String(trimmed.dropFirst(9)))
                command = ""
            } else if trimmed.lowercased().hasPrefix("/note ") {
                let title = String(trimmed.dropFirst(6))
                appState.addNote(title: title, folder: "Command Hub")
                appState.navigate(to: .notes)
            } else if trimmed.lowercased().hasPrefix("/project ") {
                let title = String(trimmed.dropFirst(9))
                appState.addProject(
                    title: title,
                    course: .general,
                    deadline: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                )
                appState.navigate(to: .projects)
            } else {
                let interpretation = CommandInterpreter.interpret(trimmed, spaces: appState.spaces)
                switch interpretation.intent {
                case .createTask:
                    appState.createTask(from: interpretation.draft)
                    appState.statusMessage = "Created \(interpretation.draft.title)"
                    command = ""
                    scope = .today
                case .rescheduleTask(let query):
                    if let task = appState.rescheduleTask(matching: query, to: interpretation.draft.dueDate) {
                        appState.statusMessage = "Moved \(task.title) to \(interpretation.draft.dueDate.formatted(date: .abbreviated, time: .shortened))"
                        command = ""
                        scope = .today
                    } else {
                        appState.statusMessage = "No task matched “\(query)”"
                    }
                case .search:
                    scope = .search
                }
            }
        }
    }

    private func filteredHints(for input: String) -> [CommandHint] {
        let lowered = input.lowercased()
        guard !lowered.isEmpty, lowered != "/" else { return hints }
        return hints.filter { $0.command.lowercased().contains(lowered) || $0.detail.lowercased().contains(lowered) }
    }

    private func intentIcon(_ intent: CommandIntent) -> String {
        switch intent {
        case .createTask: "checkmark.square"
        case .rescheduleTask: "calendar.badge.clock"
        case .search: "magnifyingglass"
        }
    }
}

private struct CommandHint: Identifiable {
    let command: String
    let detail: String
    let icon: String
    var id: String { command }
}

private struct CaptureRow: View {
    @EnvironmentObject private var appState: AppState
    let capture: WhiteboardCapture

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(capture.text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(3)
            HStack(spacing: 8) {
                Text(capture.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let taskID = capture.linkedTaskID {
                    Button("Task") {
                        appState.selectedTaskID = taskID
                        appState.navigate(to: .tasks)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HubPalette.hubAccent)
                } else {
                    Button("→ Task") { appState.convertCaptureToTask(capture.id) }
                        .buttonStyle(.plain)
                }
                if let noteID = capture.linkedNoteID {
                    Button("Note") {
                        appState.openNote(noteID)
                        appState.navigate(to: .notes)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HubPalette.hubAccent)
                } else {
                    Button("→ Note") { appState.convertCaptureToNote(capture.id) }
                        .buttonStyle(.plain)
                }
                Button(role: .destructive) { appState.deleteCapture(capture.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(10)
        .background(HubPalette.selected.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

private struct TaskRow: View {
    @EnvironmentObject private var appState: AppState
    let task: HubTask

    var body: some View {
        HStack(spacing: 12) {
            Button {
                appState.toggleComplete(task.id)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(task.course.accent)
                .frame(width: 3, height: 40)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                Text(task.course.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(Calendar.current.isDateInToday(task.dueDate) ? "Today" : task.dueDate.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.tint)
                Text(task.dueTimeLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Image(systemName: appState.selectedTaskID == task.id ? "chevron.up" : "ellipsis")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 72)
        .background(appState.selectedTaskID == task.id ? Color.accentColor.opacity(0.10) : .clear)
    }
}

private struct TaskDetail: View {
    @EnvironmentObject private var appState: AppState
    let task: HubTask

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            detailLine(icon: "clock", text: "Due \(task.dueTimeLabel)")
            detailLine(icon: "tag", text: task.course.title)

            if let projectID = task.projectID,
               let project = appState.projects.first(where: { $0.id == projectID }) {
                detailLine(icon: "folder", text: "Project: \(project.title)")
            }
            if let noteID = task.linkedNoteID,
               let note = appState.notes.first(where: { $0.id == noteID }) {
                detailLine(icon: "doc.text", text: note.title)
                    .foregroundStyle(.tint)
            }

            HStack(spacing: 10) {
                Button("Schedule", systemImage: "calendar.badge.plus") {
                    appState.schedule(task.id, at: 16)
                }
                .buttonStyle(HubProminentButtonStyle())

                Button("Open note", systemImage: "doc.text") {
                    guard let noteID = task.linkedNoteID else { return }
                    appState.openNote(noteID)
                    appState.navigate(to: .notes)
                }
                    .buttonStyle(.bordered)
                    .disabled(task.linkedNoteID == nil)

                Button("Complete", systemImage: "checkmark.circle") {
                    appState.toggleComplete(task.id)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 14)
        .background(Color.accentColor.opacity(0.07))
    }

    private func detailLine(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

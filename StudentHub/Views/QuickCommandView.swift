import SwiftUI

struct QuickCommandView: View {
    enum Action: String, CaseIterable {
        case createTask = "Create task"
        case capture = "Save to scratchpad"
        case reschedule = "Reschedule task"
        case schedule = "Schedule"
        case addProject = "Add project"
        case createNote = "Create note"
        case searchNotes = "Search notes"
        case searchFiles = "Search files"

        var icon: String {
            switch self {
            case .createTask: "checkmark.square"
            case .capture: "square.and.pencil"
            case .reschedule: "calendar.badge.clock"
            case .schedule: "calendar"
            case .addProject: "folder"
            case .createNote: "doc.text"
            case .searchNotes, .searchFiles: "magnifyingglass"
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @State private var input = "chem lab report tomorrow 7:30 pm"
    @State private var selectedAction: Action = .createTask
    @FocusState private var inputFocused: Bool
    let onDismiss: () -> Void

    private var draft: QuickCommandDraft {
        CommandParser.parse(input, spaces: appState.spaces)
    }

    private var interpretation: CommandInterpretation {
        CommandInterpreter.interpret(input, spaces: appState.spaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            inputRow
            Divider()

            GeometryReader { proxy in
                if proxy.size.width >= 620 {
                    HStack(spacing: 0) {
                        actions
                            .frame(width: proxy.size.width * 0.48)
                        Divider()
                        preview
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            actions
                            Divider()
                            preview
                        }
                    }
                }
            }

            footer
        }
        .frame(minWidth: 360, idealWidth: 780, minHeight: 390, idealHeight: 390)
        .background(Color.hubGrouped)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.hubSeparator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 24, y: 10)
        .preferredColorScheme(appState.appearance.colorScheme)
        .onAppear {
            DispatchQueue.main.async { inputFocused = true }
        }
        .onChange(of: input) { _, _ in
            if case .rescheduleTask = interpretation.intent {
                selectedAction = .reschedule
            } else if selectedAction == .reschedule {
                selectedAction = .createTask
            }
        }
        #if os(macOS)
        .onExitCommand(perform: onDismiss)
        #endif
    }

    private var inputRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "command")
                .foregroundStyle(.secondary)

            TextField("Capture, search, or run a command", text: $input)
                .font(.title3)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit(executeAction)

            Button(action: executeAction) {
                Image(systemName: "return")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BEST MATCH")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)

            QuickActionRow(title: Action.createTask.rawValue, icon: Action.createTask.icon, isSelected: selectedAction == .createTask) {
                selectedAction = .createTask
            }

            QuickActionRow(title: Action.capture.rawValue, icon: Action.capture.icon, isSelected: selectedAction == .capture) {
                selectedAction = .capture
            }

            Text("ACTIONS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 2)

            QuickActionRow(title: Action.reschedule.rawValue, icon: Action.reschedule.icon, isSelected: selectedAction == .reschedule) { selectedAction = .reschedule }
            QuickActionRow(title: Action.schedule.rawValue, icon: Action.schedule.icon, isSelected: selectedAction == .schedule) { selectedAction = .schedule }
            QuickActionRow(title: Action.addProject.rawValue, icon: Action.addProject.icon, isSelected: selectedAction == .addProject) { selectedAction = .addProject }
            QuickActionRow(title: Action.createNote.rawValue, icon: Action.createNote.icon, isSelected: selectedAction == .createNote) { selectedAction = .createNote }

            Text("SEARCH")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 2)

            QuickActionRow(title: Action.searchNotes.rawValue, icon: Action.searchNotes.icon, isSelected: selectedAction == .searchNotes) { selectedAction = .searchNotes }
            QuickActionRow(title: Action.searchFiles.rawValue, icon: Action.searchFiles.icon, isSelected: selectedAction == .searchFiles) { selectedAction = .searchFiles }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PREVIEW")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Image(systemName: selectedAction.icon)
                    .font(.title3)
                Text(selectedAction == .reschedule ? interpretation.summary : draft.title)
                    .font(.headline)
            }

            if draft.recognizedTokens.isEmpty {
                Text("Try “Jul 22”, “in 3 days”, “next Tue”, “7月20日”, or “下周三下午4点”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(draft.recognizedTokens) { token in
                            Label(token.text, systemImage: token.icon)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .frame(height: 25)
                                .background(HubPalette.selected)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            LabeledContent("Subject") {
                Label(draft.course.title, systemImage: "circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(draft.course.accent)
            }

            LabeledContent("Due") {
                Text(draft.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
            }

            Divider()

            if let note = draft.linkedNote {
                Label(note, systemImage: "doc.text")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button(selectedAction.rawValue, action: executeAction)
                    .buttonStyle(HubProminentButtonStyle())
                if selectedAction == .createTask {
                    Button("Create + schedule") {
                        let task = appState.addTask(title: draft.title, course: draft.course, dueDate: draft.dueDate)
                        let components = Calendar.current.dateComponents([.hour, .minute], from: draft.dueDate)
                        appState.schedule(task.id, at: Double(components.hour ?? 16) + Double(components.minute ?? 0) / 60, on: draft.dueDate)
                        onDismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.small)
        }
        .padding(14)
    }

    private var footer: some View {
        HStack {
            Text("↵ Run")
            Spacer()
            Text("⌥ Space")
            Spacer()
            Text("⌘K Actions")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .overlay(alignment: .top) { Divider() }
    }

    private func executeAction() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch selectedAction {
        case .createTask:
            appState.createTask(from: draft)
        case .capture:
            appState.addCapture(trimmed)
        case .reschedule:
            guard case .rescheduleTask(let query) = interpretation.intent else {
                appState.statusMessage = "Try: move Essay draft to tomorrow 4 pm"
                return
            }
            if let task = appState.rescheduleTask(matching: query, to: draft.dueDate) {
                appState.statusMessage = "Moved \(task.title) to \(draft.dueDate.formatted(date: .abbreviated, time: .shortened))"
            } else {
                appState.statusMessage = "No task matched “\(query)”"
                return
            }
        case .schedule:
            let task = appState.addTask(title: draft.title, course: draft.course, dueDate: draft.dueDate)
            let components = Calendar.current.dateComponents([.hour, .minute], from: draft.dueDate)
            let hour = Double(components.hour ?? 16) + Double(components.minute ?? 0) / 60
            appState.schedule(task.id, at: hour, on: draft.dueDate)
            appState.navigate(to: .calendar)
        case .addProject:
            appState.addProject(title: draft.title, course: draft.course, deadline: draft.dueDate)
            appState.navigate(to: .projects)
        case .createNote:
            let note = appState.addNote(title: draft.title, folder: draft.course.title, course: draft.course)
            appState.openNote(note.id)
            appState.navigate(to: .notes)
        case .searchNotes:
            if let note = appState.notes.first(where: { $0.title.localizedCaseInsensitiveContains(trimmed) || $0.markdown.localizedCaseInsensitiveContains(trimmed) }) {
                appState.openNote(note.id)
            }
            appState.navigate(to: .notes)
        case .searchFiles:
            if let item = appState.files.first(where: { $0.displayName.localizedCaseInsensitiveContains(trimmed) || $0.annotationNotes.localizedCaseInsensitiveContains(trimmed) }) {
                appState.selectedFileID = item.id
            }
            appState.navigate(to: .files)
        }
        onDismiss()
    }
}

private struct QuickActionRow: View {
    let title: String
    let icon: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isSelected ? Color.hubGroupedSecondary : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }
}

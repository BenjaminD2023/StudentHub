import SwiftUI

/// Quick Command (Spotlight) — polished command palette triggered
/// by ⌥-Space. Lets the user run natural-language commands like
/// "chem lab report tomorrow 7:30 pm" to create tasks, capture
/// thoughts, search, and more.
struct QuickCommandView: View {
    enum Action: String, CaseIterable {
        case createTask = "Create task"
        case capture = "Save to scratchpad"
        case reschedule = "Reschedule task"
        case schedule = "Schedule on calendar"
        case addProject = "Add project"
        case createNote = "Create note"
        case startTimer = "Start timer"
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
            case .startTimer: "timer"
            case .searchNotes, .searchFiles: "magnifyingglass"
            }
        }

        var tint: Color {
            switch self {
            case .createTask, .schedule, .reschedule: return HubPalette.hubAccent
            case .capture, .createNote: return HubPalette.success
            case .addProject: return HubPalette.yellow
            case .startTimer: return Color(red: 0.35, green: 0.48, blue: 0.95)
            case .searchNotes, .searchFiles: return Color(red: 0.55, green: 0.4, blue: 0.85)
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @State private var input = ""
    @State private var selectedAction: Action = .createTask
    @FocusState private var inputFocused: Bool
    let onDismiss: () -> Void

    private var draft: QuickCommandDraft {
        interpretation.draft
    }

    private var interpretation: CommandInterpretation {
        CommandInterpreter.interpret(input, spaces: appState.spaces)
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSlashInput: Bool { trimmedInput.hasPrefix("/") }
    private var isSlashSchedule: Bool {
        let lowered = trimmedInput.lowercased()
        return lowered == "/schedule" || lowered.hasPrefix("/schedule ")
    }
    private var showsSlashBrowser: Bool {
        isSlashInput && !isSlashSchedule && !SlashCommandDefinition.hasEnteredArgument(in: input)
    }

    private var existingScheduleQuery: String {
        guard case .scheduleExistingTask(let query) = interpretation.intent else { return "" }
        return query
    }

    var body: some View {
        VStack(spacing: 0) {
            inputBar
            Divider()

            GeometryReader { proxy in
                let compact = proxy.size.width < 620
                if showsSlashBrowser {
                    slashBrowser
                } else if compact {
                    ScrollView {
                        VStack(spacing: 0) {
                            if isSlashSchedule {
                                scheduleTaskPicker
                                    .padding(16)
                            } else {
                                actionsList
                            }
                            Divider()
                            preview
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        if isSlashSchedule {
                            ScrollView {
                                scheduleTaskPicker
                                    .padding(16)
                            }
                            .frame(width: max(300, proxy.size.width * 0.46))
                        } else {
                            actionsList
                                .frame(width: max(300, proxy.size.width * 0.46))
                        }
                        Divider()
                        preview
                    }
                }
            }

            footer
        }
        .frame(minWidth: 360, idealWidth: 820, minHeight: 460, idealHeight: 500)
        .background(Color.hubGrouped)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.hubSeparator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 30, y: 12)
        .preferredColorScheme(appState.appearance.colorScheme)
        .onAppear {
            DispatchQueue.main.async { inputFocused = true }
        }
        .onChange(of: input) { _, _ in
            updateSuggestedAction()
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .quickPanelWillOpen)) { _ in reset() }
        .onExitCommand(perform: onDismiss)
        .onMoveCommand { direction in
            switch direction {
            case .up: moveSelection(by: -1)
            case .down: moveSelection(by: 1)
            default: break
            }
        }
        #endif
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [HubPalette.hubAccent, HubPalette.hubAccent.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 30, height: 30)
                Image(systemName: "command")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            TextField("Capture, search, or run a command", text: $input)
                .font(.system(size: 17, weight: .medium))
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit(executeAction)
            if !input.isEmpty {
                Button { input = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button(action: executeAction) {
                Image(systemName: "return")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(HubPalette.hubAccent, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 18)
        .frame(height: 64)
    }

    // MARK: - Actions list

    private var slashBrowser: some View {
        ScrollView {
            slashCommandList
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var slashCommandList: some View {
        let commands = SlashCommandDefinition.matching(input)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Slash commands", systemImage: "command")
                    .font(.headline)
                Spacer()
                Text("\(commands.count) available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if commands.isEmpty {
                Label("No command matches “\(trimmedInput)”.", systemImage: "questionmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                        Button {
                            input = command.insertionText
                            DispatchQueue.main.async { inputFocused = true }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: command.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(HubPalette.hubAccent)
                                    .frame(width: 28, height: 28)
                                    .background(HubPalette.hubAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(command.usage)
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(HubPalette.primaryText)
                                    Text(command.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: command.takesArgument ? "arrow.right" : "return")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(command.detail)

                        if index < commands.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color.hubGrouped)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var scheduleTaskPicker: some View {
        let tasks = appState.schedulableTasks(matching: existingScheduleQuery)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Select a task")
                        .font(.headline)
                    Text("Then type its date and time after “at”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(tasks.count) matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if tasks.isEmpty {
                Label("No unfinished task matches “\(existingScheduleQuery)”.", systemImage: "magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(tasks.prefix(12).enumerated()), id: \.element.id) { index, task in
                        Button {
                            input = "/schedule \(task.title) at "
                            DispatchQueue.main.async { inputFocused = true }
                        } label: {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(task.course.accent)
                                    .frame(width: 4, height: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(HubPalette.primaryText)
                                        .lineLimit(1)
                                    Text([task.course.title, task.estimatedDurationLabel].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                let blockCount = appState.scheduleBlocks.filter { $0.linkedTaskID == task.id }.count
                                if blockCount > 0 {
                                    Text("\(blockCount) block\(blockCount == 1 ? "" : "s")")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(HubPalette.hubAccent)
                                }
                                Image(systemName: "arrow.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                appState.deleteTask(task.id)
                            } label: {
                                Label("Delete task", systemImage: "trash")
                            }
                        }

                        if index < min(tasks.count, 12) - 1 {
                            Divider().padding(.leading, 28)
                        }
                    }
                }
                .background(Color.hubGrouped)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text("Create a new one with: schedule Essay outline at 4 pm 45m")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var actionsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                actionGroup(title: "Best match", actions: [.createTask, .capture])
                actionGroup(title: "Actions", actions: [.startTimer, .reschedule, .schedule, .addProject, .createNote])
                actionGroup(title: "Search", actions: [.searchNotes, .searchFiles])
            }
            .padding(.vertical, 8)
        }
    }

    private func actionGroup(title: String, actions: [Action]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ForEach(actions, id: \.self) { action in
                QuickActionRow(
                    title: action.rawValue,
                    icon: action.icon,
                    tint: action.tint,
                    isSelected: selectedAction == action
                ) {
                    selectedAction = action
                }
            }
        }
    }

    // MARK: - Preview

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("PREVIEW")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if !previewTokens.isEmpty {
                        Text("\(previewTokens.count) detected")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(HubPalette.hubAccent)
                    }
                }

                previewHeader

                tokenChips

                if previewTokens.isEmpty, selectedActionUsesDate {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(HubPalette.yellow)
                            .font(.callout)
                        Text("Try “Jul 22”, “in 3 days”, “7月20日”, or “下周三下午4点”.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HubPalette.yellow.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if selectedAction == .capture {
                    Label("This stays in Scratchpad until you turn it into a task or note.", systemImage: "tray.full")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                metadataBlock

                Spacer(minLength: 4)

                actionButtons
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var previewHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selectedAction.tint.opacity(0.16))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: selectedAction.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(selectedAction.tint)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(previewTitle)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(HubPalette.primaryText)
                    .lineLimit(2)
                Text(previewSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var previewTitle: String {
        if selectedAction == .capture {
            return captureText.isEmpty ? "Save thought" : captureText
        }
        if selectedAction == .reschedule {
            if case .rescheduleTask(let query) = interpretation.intent {
                return "Reschedule “\(query)”"
            }
            return "Reschedule task"
        }
        if selectedAction == .schedule { return draft.title.isEmpty ? "Schedule" : draft.title }
        if selectedAction == .startTimer {
            switch selectedTimerCommand {
            case .countdown(let seconds): return "\(durationLabel(seconds)) countdown"
            case .stopwatch: return "Stopwatch"
            }
        }
        if selectedAction == .addProject, draft.title == "Untitled task" { return "Untitled project" }
        if selectedAction == .createNote, draft.title == "Untitled task" { return "Untitled note" }
        return draft.title
    }

    private var previewSubtitle: String {
        switch selectedAction {
        case .createTask: return "A new task will be created"
        case .capture: return "Saved to your scratchpad"
        case .reschedule: return "Find the matching task and move it"
        case .schedule: return "Adds a colored block to the calendar"
        case .addProject: return "A new project will be created"
        case .createNote: return "A new markdown note will open"
        case .startTimer: return "Runs across every Student Hub workspace"
        case .searchNotes, .searchFiles: return "Search the workspace"
        }
    }

    private var tokenChips: some View {
        Group {
            if !previewTokens.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(previewTokens) { token in
                            HStack(spacing: 5) {
                                Image(systemName: token.icon)
                                    .font(.system(size: 10, weight: .bold))
                                Text(token.text)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(tokenColor(token).opacity(0.14))
                            .foregroundStyle(tokenColor(token))
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private func tokenColor(_ token: CommandToken) -> Color {
        switch token.kind {
        case .date: return HubPalette.hubAccent
        case .time: return Color(red: 0.95, green: 0.5, blue: 0.2)
        case .course: return draft.course.accent
        case .estimate: return HubPalette.success
        }
    }

    @ViewBuilder
    private var metadataBlock: some View {
        switch selectedAction {
        case .capture:
            VStack(spacing: 0) {
                metadataRow(icon: "tray.full.fill", iconColor: HubPalette.success, label: "Destination", value: "Scratchpad")
                Divider().padding(.leading, 36)
                metadataRow(icon: "clock", iconColor: HubPalette.secondaryText, label: "Saved", value: "Now")
            }
            .background(Color.hubGroupedSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .createNote:
            VStack(spacing: 0) {
                metadataRow(icon: "folder.fill", iconColor: draft.course.accent, label: "Folder", value: draft.course.title)
                Divider().padding(.leading, 36)
                metadataRow(icon: "doc.text.fill", iconColor: HubPalette.success, label: "Format", value: "Markdown")
            }
            .background(Color.hubGroupedSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .startTimer:
            VStack(spacing: 0) {
                metadataRow(icon: "timer", iconColor: selectedAction.tint, label: "Mode", value: timerModeLabel)
                Divider().padding(.leading, 36)
                metadataRow(icon: "play.fill", iconColor: HubPalette.success, label: "Starts", value: "Immediately")
            }
            .background(Color.hubGroupedSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .searchNotes, .searchFiles:
            metadataRow(
                icon: "magnifyingglass",
                iconColor: selectedAction.tint,
                label: "Results",
                value: "\(searchResultCount) found"
            )
            .background(Color.hubGroupedSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        default:
            datedMetadata
        }
    }

    private var datedMetadata: some View {
        VStack(spacing: 0) {
            metadataRow(icon: "tag.fill", iconColor: draft.course.accent, label: "Space", value: draft.course.title)
            Divider().padding(.leading, 36)
            metadataRow(
                icon: "calendar",
                iconColor: HubPalette.hubAccent,
                label: selectedAction == .addProject ? "Deadline" : (selectedAction == .schedule ? "Planned" : "Due"),
                value: metadataDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
            )
            if selectedAction == .schedule, draft.plannedDate != nil {
                Divider().padding(.leading, 36)
                metadataRow(
                    icon: "calendar.badge.exclamationmark",
                    iconColor: HubPalette.yellow,
                    label: "Due",
                    value: draft.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                )
            }
            if let estimate = draft.estimatedMinutes,
               selectedAction == .createTask || selectedAction == .schedule {
                Divider().padding(.leading, 36)
                metadataRow(icon: "hourglass", iconColor: HubPalette.success, label: "Predicted time", value: estimate.studyDurationLabel)
            }
            if let note = draft.linkedNote {
                Divider().padding(.leading, 36)
                metadataRow(icon: "doc.text.fill", iconColor: Color(red: 0.4, green: 0.7, blue: 0.4), label: "Linked note", value: note)
            }
        }
        .background(Color.hubGroupedSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metadataRow(icon: String, iconColor: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.weight(.medium))
                .foregroundStyle(HubPalette.primaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button(action: executeAction) {
                Text(buttonLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(LinearGradient(
                        colors: [selectedAction.tint, selectedAction.tint.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)

            if selectedAction == .createTask {
                Button {
                    let task = appState.addTask(
                        title: draft.title,
                        course: draft.course,
                        dueDate: draft.dueDate,
                        estimatedMinutes: draft.estimatedMinutes ?? 30
                    )
                    let components = Calendar.current.dateComponents([.hour, .minute], from: draft.dueDate)
                    appState.schedule(task.id, at: Double(components.hour ?? 16) + Double(components.minute ?? 0) / 60, on: draft.dueDate)
                    onDismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.plus")
                        Text("Schedule")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HubPalette.hubAccent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38)
                    .background(HubPalette.hubAccent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var buttonLabel: String {
        switch selectedAction {
        case .createTask: return "Create task"
        case .capture: return "Save to scratchpad"
        case .reschedule: return "Reschedule"
        case .schedule: return "Add to calendar"
        case .addProject: return "Create project"
        case .createNote: return "Create note"
        case .startTimer: return "Start timer"
        case .searchNotes: return "Search notes"
        case .searchFiles: return "Search files"
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                kbd("↵")
                Text("Run")
            }
            HStack(spacing: 6) {
                kbd("↑↓")
                Text("Switch action")
            }
            HStack(spacing: 6) {
                kbd("esc")
                Text("Close")
            }
            Spacer()
            HStack(spacing: 6) {
                kbd("⌥ Space")
                Text("Toggle")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .frame(height: 42)
        .overlay(alignment: .top) { Divider() }
    }

    private func kbd(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(HubPalette.secondaryText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.hubGroupedSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(HubPalette.separator, lineWidth: 0.5)
            )
    }

    // MARK: - Actions

    private func executeAction() {
        let trimmed = trimmedInput
        guard !trimmed.isEmpty else { return }
        if appState.performSlashCommand(trimmed) {
            onDismiss()
            return
        }
        switch selectedAction {
        case .createTask:
            appState.createTask(from: draft)
        case .capture:
            guard !captureText.isEmpty else {
                appState.statusMessage = "Type something to capture"
                return
            }
            appState.addCapture(captureText)
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
            if case .scheduleExistingTask(let query) = interpretation.intent {
                guard let task = appState.scheduleTask(
                    matching: query,
                    to: interpretation.plannedDate,
                    durationMinutes: draft.estimatedMinutes
                ) else {
                    appState.statusMessage = query.isEmpty ? "Choose a task after /schedule" : "No task matched “\(query)”"
                    return
                }
                appState.statusMessage = "Scheduled \(task.title) for \(interpretation.plannedDate.formatted(date: .abbreviated, time: .shortened))"
            } else {
                appState.createScheduledTask(from: draft)
            }
            appState.navigate(to: .today)
        case .addProject:
            let project = appState.addProject(title: projectTitle, course: draft.course, deadline: projectDeadline)
            appState.statusMessage = "Created project \(project.title)"
            appState.navigate(to: .projects)
        case .createNote:
            let note = appState.addNote(title: noteTitle, folder: draft.course.title, course: draft.course)
            appState.openNote(note.id)
            appState.navigate(to: .notes)
        case .startTimer:
            appState.startFocusTimer(selectedTimerCommand)
            appState.navigate(to: .pomodoro)
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

    private var captureText: String {
        if case .capture(let text) = interpretation.intent { return text }
        return input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var projectTitle: String { draft.title == "Untitled task" ? "Untitled project" : draft.title }
    private var noteTitle: String { draft.title == "Untitled task" ? "Untitled note" : draft.title }
    private var projectDeadline: Date {
        draft.recognizedTokens.contains(where: { $0.kind == .date })
            ? draft.dueDate
            : (Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
    }

    private var searchResultCount: Int {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        switch selectedAction {
        case .searchNotes:
            return appState.notes.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.markdown.localizedCaseInsensitiveContains(query) }.count
        case .searchFiles:
            return appState.files.filter { $0.displayName.localizedCaseInsensitiveContains(query) || $0.annotationNotes.localizedCaseInsensitiveContains(query) }.count
        default:
            return 0
        }
    }

    private var previewTokens: [CommandToken] {
        switch selectedAction {
        case .capture, .startTimer, .searchNotes, .searchFiles: []
        default: draft.recognizedTokens
        }
    }

    private var selectedActionUsesDate: Bool {
        switch selectedAction {
        case .createTask, .reschedule, .schedule, .addProject: true
        case .capture, .createNote, .startTimer, .searchNotes, .searchFiles: false
        }
    }

    private var metadataDate: Date {
        if selectedAction == .addProject { return projectDeadline }
        if selectedAction == .schedule { return interpretation.plannedDate }
        return draft.dueDate
    }

    private func updateSuggestedAction() {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedAction = .createTask
            return
        }
        switch interpretation.intent {
        case .capture: selectedAction = .capture
        case .scheduleTask: selectedAction = .schedule
        case .scheduleExistingTask: selectedAction = .schedule
        case .createProject: selectedAction = .addProject
        case .createNote: selectedAction = .createNote
        case .rescheduleTask: selectedAction = .reschedule
        case .search: break
        case .startTimer: selectedAction = .startTimer
        case .createTask:
            if selectedAction == .reschedule || selectedAction == .startTimer { selectedAction = .createTask }
        }
    }

    private func moveSelection(by offset: Int) {
        let actions = Action.allCases
        guard let index = actions.firstIndex(of: selectedAction) else { return }
        selectedAction = actions[(index + offset + actions.count) % actions.count]
    }

    private func reset() {
        input = ""
        selectedAction = .createTask
        DispatchQueue.main.async { inputFocused = true }
    }

    private var selectedTimerCommand: FocusTimerCommand {
        if case .startTimer(let command) = interpretation.intent { return command }
        return .countdown(seconds: 25 * 60)
    }

    private var timerModeLabel: String {
        switch selectedTimerCommand {
        case .countdown(let seconds): "Countdown · \(durationLabel(seconds))"
        case .stopwatch: "Stopwatch · count up"
        }
    }

    private func durationLabel(_ seconds: Int) -> String {
        if seconds.isMultiple(of: 3600) { return "\(seconds / 3600) hr" }
        if seconds.isMultiple(of: 60) { return "\(seconds / 60) min" }
        return "\(seconds) sec"
    }
}

// MARK: - Action row

private struct QuickActionRow: View {
    let title: String
    let icon: String
    let tint: Color
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(isSelected ? 0.22 : 0.10))
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                    )
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(HubPalette.primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? HubPalette.selected : Color.clear)
            )
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: isSelected)
    }
}

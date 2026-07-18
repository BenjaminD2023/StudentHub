import SwiftUI

/// iPhone More tab. 2-column grid of secondary workspaces, plus a
/// sync settings section and spaces management.
struct IPhoneMoreView: View {
    @EnvironmentObject private var appState: AppState

    private var workspaceCards: [MoreCardModel] {
        [
            MoreCardModel(title: "Projects", count: "\(appState.projects.count) active", icon: "folder.fill", tint: HubPalette.hubAccent, section: .projects),
            MoreCardModel(title: "Files & PDFs", count: "\(appState.files.count) imported", icon: "doc.fill", tint: HubPalette.red, section: .files),
            MoreCardModel(title: "Journal", count: "\(appState.journalEntries.count) entries", icon: "book.fill", tint: HubPalette.hubAccent, section: .journal),
            MoreCardModel(title: "Meetings", count: "\(thisWeekMeetings()) this week", icon: "person.3.fill", tint: HubPalette.hubAccent, section: .meetings),
            MoreCardModel(title: "Reminders", count: "\(pendingReminders()) pending", icon: "bell.fill", tint: HubPalette.yellow, section: .reminders),
            MoreCardModel(title: "Pomodoro", count: pomodoroLabel, icon: "timer", tint: HubPalette.hubAccent, section: .pomodoro),
            MoreCardModel(title: "Export", count: "CSV or Markdown", icon: "square.and.arrow.up", tint: HubPalette.hubAccent, section: .export),
            MoreCardModel(title: "Spaces", count: "\(appState.spaces.count) configured", icon: "rectangle.3.group.fill", tint: HubPalette.hubAccent, section: .spaceHome)
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(workspaceCards) { model in
                            Button { appState.navigate(to: model.section) } label: {
                                MoreCard(title: model.title, count: model.count, iconName: model.icon, tint: model.tint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Workspaces")
                        .textCase(nil)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(HubPalette.secondaryText)
                }

                Section {
                    HStack {
                        Image(systemName: appState.isCloudSyncEnabled ? "checkmark.icloud.fill" : "icloud.slash")
                            .foregroundStyle(appState.isCloudSyncEnabled ? HubPalette.success : HubPalette.tertiaryText)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("iCloud sync")
                            Text(syncDetail)
                                .font(.system(size: 12))
                                .foregroundStyle(HubPalette.secondaryText)
                        }
                        Spacer()
                        Toggle("", isOn: $appState.isCloudSyncEnabled)
                            .labelsHidden()
                    }
                } header: {
                    Text("Sync")
                        .textCase(nil)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(HubPalette.secondaryText)
                }

                Section {
                    Picker("Appearance", selection: $appState.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon).tag(mode)
                        }
                    }
                } header: {
                    Text("Appearance")
                        .textCase(nil)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(HubPalette.secondaryText)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle("More")
            .refreshable { await appState.syncNow() }
        }
    }

    private var pomodoroLabel: String {
        appState.pomodoroRunning ? "Running · \(appState.pomodoroLabel)" : "Idle · \(appState.pomodoroLabel)"
    }

    private var syncDetail: String {
        if !appState.isCloudSyncEnabled { return "Local saving only" }
        switch appState.cloudSyncStatus {
        case .synced: return "Up to date"
        case .syncing: return "Syncing…"
        case .checking: return "Checking…"
        case .unavailable(let m): return m
        case .localOnly: return "Local only"
        }
    }

    private func thisWeekMeetings() -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        return appState.meetings.filter { $0.date >= weekStart }.count
    }

    private func pendingReminders() -> Int {
        appState.reminders.filter { !$0.isCompleted }.count
    }
}

private struct MoreCardModel: Identifiable {
    let id = UUID()
    let title: String
    let count: String
    let icon: String
    let tint: Color
    let section: HubSection
}

struct IPhoneSpacesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editingSpace: Course?
    @State private var isCreatingSpace = false

    var body: some View {
        List {
            Section {
                ForEach(appState.spaces) { space in
                    HStack(spacing: 10) {
                        NavigationLink {
                            IPhoneSpaceHomeView(spaceID: space.id)
                        } label: {
                            HStack(spacing: 12) {
                                Circle().fill(space.accent).frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(space.title).font(.body.weight(.semibold))
                                    Text("\(appState.itemCount(in: space)) linked items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button { editingSpace = space } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(space.title)")
                    }
                }
            } footer: {
                Text("Open a Space for its tasks, notes, projects, and files. Edit lets you rename, recolor, or delete it directly.")
            }
        }
        .navigationTitle("Spaces")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isCreatingSpace = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editingSpace) { space in
            IPhoneSpaceEditorView(space: space)
        }
        .sheet(isPresented: $isCreatingSpace) {
            IPhoneSpaceEditorView(space: nil)
        }
    }
}

private struct IPhoneSpaceHomeView: View {
    @EnvironmentObject private var appState: AppState
    let spaceID: String
    @State private var editingNoteID: UUID?
    @State private var editingProjectID: UUID?
    @State private var editingFileID: UUID?

    private var space: Course? { appState.spaces.first(where: { $0.id == spaceID }) }
    private var tasks: [HubTask] { appState.tasks.filter { $0.course.id == spaceID }.sorted { $0.dueDate < $1.dueDate } }
    private var notes: [HubNote] { appState.notes.filter { $0.course.id == spaceID }.sorted { $0.modifiedAt > $1.modifiedAt } }
    private var projects: [HubProject] { appState.projects.filter { $0.course.id == spaceID && !$0.isArchived }.sorted { $0.deadline < $1.deadline } }
    private var files: [HubFileItem] { appState.files.filter { $0.course.id == spaceID }.sorted { $0.addedAt > $1.addedAt } }

    var body: some View {
        List {
            if let space {
                Section {
                    HStack {
                        summary("Open tasks", tasks.filter { !$0.isCompleted }.count, space.accent)
                        summary("Notes", notes.count, HubPalette.hubAccent)
                        summary("Projects", projects.count, HubPalette.yellow)
                    }
                }
                Section("Tasks") {
                    ForEach(tasks.filter { !$0.isCompleted }.prefix(8)) { task in
                        TaskChecklistRow(task: task)
                    }
                    Button("New task", systemImage: "plus") {
                        _ = appState.addTask(title: "New task", course: space)
                    }
                }
                Section("Recent notes") {
                    ForEach(notes.prefix(6)) { note in
                        Button { editingNoteID = note.id } label: {
                            Label(note.title, systemImage: "doc.text")
                        }
                    }
                    Button("New note", systemImage: "square.and.pencil") {
                        editingNoteID = appState.addNote(course: space).id
                    }
                }
                Section("Projects") {
                    ForEach(projects.prefix(6)) { project in
                        Button { editingProjectID = project.id } label: {
                            HStack {
                                Text(project.title)
                                Spacer()
                                Text(project.deadline.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Files") {
                    ForEach(files.prefix(6)) { file in
                        Button { editingFileID = file.id } label: {
                            Label(file.displayName, systemImage: file.kind == .pdf ? "doc.richtext" : "doc")
                        }
                    }
                }
            }
        }
        .navigationTitle(space?.title ?? "Space")
        .onAppear { appState.selectedSpaceID = spaceID }
        .sheet(item: Binding(
            get: { editingNoteID.map(IdentifiableNote.init(id:)) },
            set: { editingNoteID = $0?.id }
        )) { note in
            IPhoneNoteEditorView(noteID: note.id)
        }
        .sheet(item: Binding(
            get: { editingProjectID.map(IdentifiableTask.init(id:)) },
            set: { editingProjectID = $0?.id }
        )) { project in
            if let value = appState.projects.first(where: { $0.id == project.id }) {
                ProjectInspectorView(project: value)
            }
        }
        .sheet(item: Binding(
            get: { editingFileID.map(IdentifiableTask.init(id:)) },
            set: { editingFileID = $0?.id }
        )) { file in
            if let value = appState.files.first(where: { $0.id == file.id }) {
                FileInspectorView(item: value)
            }
        }
    }

    private func summary(_ title: String, _ value: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.title2.bold()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IPhoneSpaceEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let space: Course?
    @State private var title: String
    @State private var colorHex: UInt32
    @State private var confirmsDeletion = false

    init(space: Course?) {
        self.space = space
        _title = State(initialValue: space?.title ?? "")
        _colorHex = State(initialValue: space?.colorHex ?? Course.colorChoices.first ?? 0x5B8DEF)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Space name", text: $title) }
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 42))], spacing: 14) {
                        ForEach(Course.colorChoices, id: \.self) { color in
                            Button { colorHex = color } label: {
                                Circle()
                                    .fill(Course.color(for: color))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if color == colorHex { Image(systemName: "checkmark").foregroundStyle(.white).font(.caption.bold()) }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let space, appState.spaces.count > 1 {
                    Section {
                        Button("Delete Space & Contents", role: .destructive) { confirmsDeletion = true }
                    } footer: {
                        Text("Deletes every task, calendar block, project, note, and file assigned to \(space.title).")
                    }
                }
            }
            .navigationTitle(space == nil ? "New Space" : "Edit Space")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Delete \(space?.title ?? "Space") and everything inside?", isPresented: $confirmsDeletion) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Everything", role: .destructive) {
                    if let space { appState.deleteSpaceAndContents(space.id) }
                    dismiss()
                }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    private func save() {
        if var space {
            space.title = title
            space.colorHex = colorHex
            appState.updateSpace(space)
        } else {
            _ = appState.addSpace(title: title, colorHex: colorHex)
        }
        dismiss()
    }
}

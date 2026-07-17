import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsSpaceManager = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SidebarSection(title: "NOW") {
                    SidebarNavigationRow(section: .today)
                    SidebarNavigationRow(section: .inbox, trailing: "\(appState.tasks.filter { !$0.isCompleted }.count)")
                    SidebarNavigationRow(section: .calendar)
                }

                SidebarSection(title: "PLAN") {
                    SidebarNavigationRow(section: .tasks)
                    SidebarNavigationRow(section: .projects)
                    SidebarNavigationRow(section: .reminders)
                    SidebarNavigationRow(section: .pomodoro)
                }

                SidebarSection(title: "SPACES") {
                    ForEach(appState.spaces) { space in
                        Button {
                            appState.taskCourseFilter = space
                            appState.navigate(to: .tasks)
                        } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(space.accent)
                                    .frame(width: 4, height: 24)
                                Text(space.title)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(appState.tasks.filter { $0.course.id == space.id && !$0.isCompleted }.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 35)
                            .background(isSelected(space) ? space.accent.opacity(0.12) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button { showsSpaceManager = true } label: {
                        Label("Manage Spaces", systemImage: "plus.circle")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color.hubAccent)
                            .padding(.horizontal, 9)
                            .frame(height: 34)
                    }
                    .buttonStyle(.plain)
                }

                SidebarSection(title: "LIBRARY") {
                    SidebarNavigationRow(section: .notes)
                    SidebarNavigationRow(section: .files)
                    SidebarNavigationRow(section: .journal)
                    SidebarNavigationRow(section: .meetings)
                }

                SidebarSection(title: "OUTPUT") {
                    SidebarNavigationRow(section: .export)
                }
            }
            .padding(14)
        }
        .sheet(isPresented: $showsSpaceManager) {
            SpaceManagerView()
                .environmentObject(appState)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Menu {
                    Toggle("Sync with iCloud", isOn: $appState.isCloudSyncEnabled)
                    if appState.isCloudSyncEnabled {
                        Button("Sync now") { Task { await appState.syncNow() } }
                    }
                    if let detail = appState.cloudSyncDetail {
                        Text(detail)
                    } else {
                        Text("Local data is always saved first.")
                    }
                } label: {
                    Label(appState.cloudSyncStatus.title, systemImage: appState.cloudSyncStatus.icon)
                        .font(.caption)
                        .foregroundStyle(syncStatusColor)
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif
                .fixedSize()
                Spacer()
                Menu {
                    Picker("Appearance", selection: $appState.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: appState.appearance.icon)
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif
                .fixedSize()
            }
            .padding(16)
            .background(Color.hubSidebar)
        }
        .background(Color.hubSidebar)
    }

    private var syncStatusColor: Color {
        if case .unavailable = appState.cloudSyncStatus { return HubPalette.red }
        return HubPalette.secondaryText
    }

    private func isSelected(_ space: Course) -> Bool {
        appState.selectedSection == .tasks && appState.taskCourseFilter?.id == space.id
    }
}

private struct SpaceManagerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var newTitle = ""
    @State private var newColor = Course.colorChoices.first ?? 0x5B8DEF

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Make the structure fit your brain.")
                        .font(.title3.weight(.semibold))
                    Text("Spaces flow through tasks, calendar, projects, notes, files, and Command Hub.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    SpaceColorPicker(selection: $newColor)
                    TextField("New Space name", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .onSubmit(addSpace)
                    Button(action: addSpace) {
                        Label("Add", systemImage: "plus")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(canAdd ? Color.white : Color.secondary)
                            .padding(.horizontal, 11)
                            .frame(height: 28)
                            .background(canAdd ? Color.hubAccent : Color.hubGroupedSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .disabled(!canAdd)
                }

                Divider()

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.spaces) { space in
                            SpaceEditorRow(space: space)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(22)
            .navigationTitle("Spaces")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 540, minHeight: 500)
    }

    private func addSpace() {
        guard appState.addSpace(title: newTitle, colorHex: newColor) != nil else { return }
        newTitle = ""
        if let index = Course.colorChoices.firstIndex(of: newColor) {
            newColor = Course.colorChoices[(index + 1) % Course.colorChoices.count]
        }
    }

    private var canAdd: Bool {
        !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct SpaceEditorRow: View {
    @EnvironmentObject private var appState: AppState
    let space: Course
    @State private var title: String
    @State private var colorHex: UInt32
    @State private var showsDirectDeleteConfirmation = false

    init(space: Course) {
        self.space = space
        _title = State(initialValue: space.title)
        _colorHex = State(initialValue: space.colorHex)
    }

    var body: some View {
        HStack(spacing: 12) {
            SpaceColorPicker(selection: $colorHex)
            TextField("Space name", text: $title)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .onSubmit(save)
            Text(itemSummary)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
            Button("Save", action: save)
                .buttonStyle(.borderless)
                .disabled(!hasChanges || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if appState.spaces.count > 1 {
                Menu {
                    Button("Delete Space & Contents…", role: .destructive) {
                        showsDirectDeleteConfirmation = true
                    }
                    Divider()
                    Text("Or move its contents to…")
                    ForEach(appState.spaces.filter { $0.id != space.id }) { replacement in
                        Button("\(replacement.title) & delete", role: .destructive) {
                            appState.deleteSpace(space.id, reassignTo: replacement.id)
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(HubPalette.red)
                        .frame(width: 24, height: 24)
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .fixedSize()
                .help("Delete this Space and move its contents")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(Color.hubGroupedSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: colorHex) { _, _ in save() }
        .onChange(of: space.title) { _, newValue in title = newValue }
        .onChange(of: space.colorHex) { _, newValue in colorHex = newValue }
        .alert("Delete \(space.title) and everything inside?", isPresented: $showsDirectDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                appState.deleteSpaceAndContents(space.id)
            }
        } message: {
            Text("This permanently deletes every task, calendar block, project, note, and file assigned to this Space. This can’t be undone.")
        }
    }

    private var hasChanges: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines) != space.title || colorHex != space.colorHex
    }

    private var itemSummary: String {
        let count = appState.itemCount(in: space)
        return "\(count) item\(count == 1 ? "" : "s")"
    }

    private func save() {
        var updated = space
        updated.title = title
        updated.colorHex = colorHex
        appState.updateSpace(updated)
    }
}

private struct SpaceColorPicker: View {
    @Binding var selection: UInt32

    var body: some View {
        Menu {
            ForEach(Array(Course.colorChoices.enumerated()), id: \.element) { index, color in
                Button {
                    selection = color
                } label: {
                    Label(colorNames[index], systemImage: color == selection ? "checkmark.circle.fill" : "circle")
                }
            }
        } label: {
            Circle()
                .fill(Course.color(for: selection))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Change color")
    }

    private var colorNames: [String] {
        ["Blue", "Cyan", "Green", "Yellow", "Red", "Purple", "Orange", "Forest", "Slate", "Pink"]
    }
}

private struct SidebarSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.7)
                .padding(.horizontal, 8)
            content
        }
    }
}

private struct SidebarNavigationRow: View {
    @EnvironmentObject private var appState: AppState
    let section: HubSection
    var trailing: String? = nil

    var body: some View {
        Button {
            if section == .tasks { appState.taskCourseFilter = nil }
            appState.navigate(to: section)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .frame(width: 18)
                    .foregroundStyle(appState.selectedSection == section ? Color.hubAccent : .secondary)
                Text(section.title)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 36)
            .background(appState.selectedSection == section ? Color.hubGroupedSecondary : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

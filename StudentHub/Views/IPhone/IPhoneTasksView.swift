import SwiftUI

/// iPhone Tasks tab. Native List with sectioned grouping, search,
/// and swipe actions to complete / delete. Tapping a row opens the
/// task inspector as a sheet with a medium detent.
struct IPhoneTasksView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText: String = ""
    @State private var filter: TaskFilter = .all
    @State private var editingTaskID: UUID?

    enum TaskFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case today = "Today"
        case upcoming = "Upcoming"
        case inbox = "Inbox"
        case completed = "Completed"
        var id: String { rawValue }
    }

    private var filtered: [HubTask] {
        let calendar = Calendar.current
        let base = appState.tasks
        let filtered: [HubTask]
        switch filter {
        case .all: filtered = base
        case .today:
            filtered = base.filter { !$0.isCompleted && calendar.isDateInToday($0.dueDate) }
        case .upcoming:
            filtered = base.filter { !$0.isCompleted && $0.dueDate > Date() }
        case .inbox:
            filtered = base.filter { !$0.isCompleted && $0.projectID == nil && $0.parentTaskID == nil }
        case .completed:
            filtered = base.filter { $0.isCompleted }
        }
        guard !searchText.isEmpty else { return filtered }
        return filtered.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
            || $0.course.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedBySpace: [(Course, [HubTask])] {
        let tasks = filtered
        let spaces = appState.spaces
        var groups: [(Course, [HubTask])] = []
        let inboxTasks = tasks.filter { $0.projectID == nil && $0.parentTaskID == nil }
        if !inboxTasks.isEmpty {
            groups.append((Course(id: "_inbox", title: "Inbox", colorHex: 0x8A8F98), inboxTasks))
        }
        for space in spaces where space.id != Course.general.id {
            let items = tasks.filter { $0.course.id == space.id }
            if !items.isEmpty { groups.append((space, items)) }
        }
        let generalTasks = tasks.filter { $0.course.id == Course.general.id }
        if !generalTasks.isEmpty {
            groups.append((Course.general, generalTasks))
        }
        return groups
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    Section {
                        EmptyStateView(
                            systemImage: "checkmark.circle",
                            title: "Nothing here",
                            message: filter == .completed
                                ? "Completed tasks will appear here."
                                : "Capture a task on the Today tab to see it here."
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                ForEach(groupedBySpace, id: \.0.id) { space, tasks in
                    Section {
                        ForEach(tasks) { task in
                            Button { editingTaskID = task.id } label: {
                                TaskChecklistRow(task: task, showSpace: false)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    withAnimation { appState.toggleComplete(task.id) }
                                } label: {
                                    Label(task.isCompleted ? "Reopen" : "Done", systemImage: "checkmark")
                                }
                                .tint(HubPalette.success)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    appState.deleteTask(task.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        HStack {
                            if space.id != "_inbox" {
                                Circle().fill(space.accent).frame(width: 8, height: 8)
                            }
                            Text(space.title.uppercased())
                                .font(.system(size: 12, weight: .semibold))
                                .tracking(0.6)
                            Spacer()
                            Text("\(tasks.count)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HubPalette.tertiaryText)
                        }
                        .textCase(nil)
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle("Tasks")
            .searchable(text: $searchText, prompt: "Search tasks")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(TaskFilter.allCases) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                    } label: {
                        Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                #endif
            }
            .sheet(item: editingTaskBinding) { task in
                IPhoneTaskInspectorView(taskID: task.id)
            }
            .refreshable { await appState.syncNow() }
        }
    }

    private var editingTaskBinding: Binding<IdentifiableTask?> {
        Binding(
            get: { editingTaskID.map(IdentifiableTask.init(id:)) },
            set: { editingTaskID = $0?.id }
        )
    }
}

import SwiftUI

/// iPad Tasks view. Renders a 2-column grid of task cards grouped
/// by Space. The list style is the same `.insetGrouped` as iPhone
/// but the wider canvas allows two columns side by side.
struct IPadTasksView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText: String = ""
    @State private var editingTaskID: UUID?

    private var filtered: [HubTask] {
        let base = appState.tasks.filter { !$0.isCompleted }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
            || $0.course.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedBySpace: [(Course, [HubTask])] {
        let spaces = appState.spaces
        var groups: [(Course, [HubTask])] = []
        let inboxTasks = filtered.filter { $0.projectID == nil && $0.parentTaskID == nil }
        if !inboxTasks.isEmpty {
            groups.append((Course(id: "_inbox", title: "Inbox", colorHex: 0x8A8F98), inboxTasks))
        }
        for space in spaces {
            let items = filtered.filter { $0.course.id == space.id }
            if !items.isEmpty { groups.append((space, items)) }
        }
        return groups
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("All Tasks").font(.system(size: 22, weight: .bold))
                    Text("\(filtered.count) open").font(.system(size: 13)).foregroundStyle(HubPalette.secondaryText)
                }
                Spacer()
                searchField
                Button {
                    let task = appState.addTask(title: "New task")
                    editingTaskID = task.id
                } label: {
                    Label("New Task", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(groupedBySpace, id: \.0.id) { space, tasks in
                        spaceCard(space: space, tasks: tasks)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .background(HubPalette.background)
        .sheet(item: editingTaskBinding) { task in
            IPhoneTaskInspectorView(taskID: task.id)
        }
    }

    private func spaceCard(space: Course, tasks: [HubTask]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if space.id != "_inbox" {
                    Circle().fill(space.accent).frame(width: 10, height: 10)
                } else {
                    Image(systemName: "tray").font(.system(size: 12)).foregroundStyle(HubPalette.hubAccent)
                }
                Text(space.title.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.6)
                Spacer()
                Text("\(tasks.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HubPalette.tertiaryText)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack(spacing: 0) {
                ForEach(tasks) { task in
                    Button { editingTaskID = task.id } label: {
                        TaskChecklistRow(task: task, showSpace: false)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            appState.deleteTask(task.id)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                    if task.id != tasks.last?.id {
                        Divider().padding(.leading, 46)
                    }
                }
            }
        }
        .background(HubPalette.grouped)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HubPalette.separator, lineWidth: 0.5)
        )
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(HubPalette.tertiaryText)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .frame(width: 200)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(HubPalette.grouped)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(HubPalette.separator, lineWidth: 0.5)
        )
    }

    private var editingTaskBinding: Binding<IdentifiableTask?> {
        Binding(
            get: { editingTaskID.map(IdentifiableTask.init(id:)) },
            set: { editingTaskID = $0?.id }
        )
    }
}

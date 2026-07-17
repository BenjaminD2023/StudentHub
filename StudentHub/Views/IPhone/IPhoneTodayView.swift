import SwiftUI

/// iPhone Today dashboard: greeting, sync status, quick capture,
/// today's schedule, and the most pressing tasks.
struct IPhoneTodayView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editingTaskID: UUID?

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var todaysBlocks: [ScheduleBlock] {
        appState.scheduleBlocks
            .filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
            .sorted { $0.startHour < $1.startHour }
    }

    private var dueTodayTasks: [HubTask] {
        let calendar = Calendar.current
        return appState.tasks
            .filter { !$0.isCompleted && calendar.isDate($0.dueDate, inSameDayAs: today) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var overdueTasks: [HubTask] {
        appState.tasks
            .filter { $0.isOverdue }
            .sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TodayGreetingBanner(date: today)

                    QuickCaptureField()

                    if !todaysBlocks.isEmpty {
                        scheduleSection
                    }

                    if !dueTodayTasks.isEmpty || !overdueTasks.isEmpty {
                        tasksSection
                    }

                    quickActionsGrid

                    if todaysBlocks.isEmpty && dueTodayTasks.isEmpty && overdueTasks.isEmpty {
                        EmptyStateView(
                            systemImage: "sun.max",
                            title: "Nothing scheduled today",
                            message: "Capture a task above or add a study block to get started."
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(HubPalette.background)
            .navigationTitle("")
            #if os(iOS)

            .navigationBarTitleDisplayMode(.inline)

            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Appearance", selection: $appState.appearance) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.icon).tag(mode)
                            }
                        }
                        Divider()
                        Toggle("Sync with iCloud", isOn: $appState.isCloudSyncEnabled)
                    } label: {
                        Image(systemName: "circle.lefthalf.filled")
                    }
                }
                #endif
            }
            .sheet(item: editingTaskBinding) { task in
                IPhoneTaskInspectorView(taskID: task.id)
            }
            .refreshable {
                await appState.syncNow()
            }
        }
    }

    // MARK: - Subviews

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HubSectionHeader(title: "Schedule", trailing: nil)
            VStack(spacing: 0) {
                ForEach(todaysBlocks) { block in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(block.startHour.hourLabel)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(HubPalette.primaryText)
                            Text(block.startHour.meridiem)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(HubPalette.tertiaryText)
                        }
                        .frame(width: 52, alignment: .trailing)
                        ScheduleBlockCard(block: block)
                    }
                    .padding(.vertical, 6)
                    if block.id != todaysBlocks.last?.id {
                        Divider().padding(.leading, 62)
                    }
                }
            }
            .padding(12)
            .background(HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HubPalette.separator, lineWidth: 0.5)
            )
        }
    }

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HubSectionHeader(title: "Tasks", trailing: "\(dueTodayTasks.count + overdueTasks.count)")
                Spacer()
            }
            VStack(spacing: 0) {
                if !overdueTasks.isEmpty {
                    HubSectionHeader(title: "Overdue", trailing: "\(overdueTasks.count)")
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                    ForEach(overdueTasks) { task in
                        Button { editingTaskID = task.id } label: {
                            TaskChecklistRow(task: task)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        if task.id != overdueTasks.last?.id || !dueTodayTasks.isEmpty {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                if !dueTodayTasks.isEmpty {
                    if !overdueTasks.isEmpty {
                        HubSectionHeader(title: "Due today", trailing: "\(dueTodayTasks.count)")
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                    }
                    ForEach(dueTodayTasks) { task in
                        Button { editingTaskID = task.id } label: {
                            TaskChecklistRow(task: task)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        if task.id != dueTodayTasks.last?.id {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
            }
            .background(HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(HubPalette.separator, lineWidth: 0.5)
            )
        }
    }

    private var quickActionsGrid: some View {
        VStack(alignment: .leading, spacing: 0) {
            HubSectionHeader(title: "Quick actions")
            let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 8) {
                QuickActionTile(icon: "timer", tint: HubPalette.hubAccent, title: "Pomodoro") {
                    appState.navigate(to: .pomodoro)
                }
                QuickActionTile(icon: "square.and.pencil", tint: HubPalette.hubAccent, title: "Note") {
                    let note = appState.addNote()
                    appState.selectedNoteID = note.id
                }
                QuickActionTile(icon: "bell.badge", tint: HubPalette.yellow, title: "Reminder") {
                    appState.addReminder(title: "New reminder", dueDate: Date().addingTimeInterval(3600))
                }
                QuickActionTile(icon: "calendar.badge.plus", tint: HubPalette.hubAccent, title: "Schedule") {
                    appState.navigate(to: .calendar)
                }
            }
        }
    }

    private var editingTaskBinding: Binding<IdentifiableTask?> {
        Binding(
            get: { editingTaskID.map(IdentifiableTask.init(id:)) },
            set: { editingTaskID = $0?.id }
        )
    }
}

// MARK: - Quick action tile

private struct QuickActionTile: View {
    let icon: String
    let tint: Color
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HubPalette.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helper for `.sheet(item:)`

struct IdentifiableTask: Identifiable {
    let id: UUID
}

// MARK: - Hour label helpers

private extension Double {
    var hourLabel: String {
        let total = Int(self)
        let h = total % 12 == 0 ? 12 : total % 12
        return "\(h):00"
    }
    var meridiem: String {
        let h = Int(self)
        return h < 12 ? "AM" : "PM"
    }
}

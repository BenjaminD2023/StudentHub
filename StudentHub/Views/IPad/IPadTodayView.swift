import SwiftUI

/// iPad Today view. Two-column dashboard: schedule on the left, due
/// tasks on the right, with the quick capture and a pinned-spaces
/// row above the fold.
struct IPadTodayView: View {
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
        appState.tasks.filter { $0.isOverdue }.sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TodayGreetingBanner(date: today)
                QuickCaptureField()

                HStack(alignment: .top, spacing: 16) {
                    scheduleCard
                    tasksCard
                }

                spacesCard
            }
            .padding(20)
        }
        .background(HubPalette.background)
        .navigationTitle("Today")
        .sheet(item: editingTaskBinding) { task in
            IPhoneTaskInspectorView(taskID: task.id)
        }
    }

    // MARK: - Cards

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader(title: "Schedule")
            if todaysBlocks.isEmpty {
                EmptyStateView(
                    systemImage: "calendar",
                    title: "Open calendar",
                    message: "Add a study block in the calendar to plan your day."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(todaysBlocks) { block in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(formatHour(Int(block.startHour)))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(HubPalette.secondaryText)
                                Text(block.startHour.meridiem)
                                    .font(.system(size: 10))
                                    .foregroundStyle(HubPalette.tertiaryText)
                            }
                            .frame(width: 44, alignment: .trailing)
                            ScheduleBlockCard(block: block)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        if block.id != todaysBlocks.last?.id {
                            Divider().padding(.leading, 56)
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
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader(title: "Tasks", trailing: "\(dueTodayTasks.count + overdueTasks.count)")
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
                    }
                }
                if overdueTasks.isEmpty && dueTodayTasks.isEmpty {
                    EmptyStateView(
                        systemImage: "checkmark.circle",
                        title: "All clear",
                        message: "No tasks are due today."
                    )
                }
            }
            .background(HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(HubPalette.separator, lineWidth: 0.5)
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var spacesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader(title: "Pinned spaces")
            HStack(spacing: 14) {
                ForEach(appState.spaces) { space in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(space.accent)
                            .frame(width: 48, height: 48)
                        Text(space.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text("\(appState.tasks.filter { $0.course.id == space.id && !$0.isCompleted }.count) open")
                            .font(.system(size: 11))
                            .foregroundStyle(HubPalette.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(14)
            .background(HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(HubPalette.separator, lineWidth: 0.5)
            )
        }
    }

    private var editingTaskBinding: Binding<IdentifiableTask?> {
        Binding(
            get: { editingTaskID.map(IdentifiableTask.init(id:)) },
            set: { editingTaskID = $0?.id }
        )
    }

    private func formatHour(_ hour: Int) -> String {
        let h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(h)"
    }
}

private extension Double {
    var meridiem: String { Int(self) < 12 ? "AM" : "PM" }
}

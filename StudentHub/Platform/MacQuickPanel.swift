#if os(macOS)
import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let quickPanelWillOpen = Notification.Name("StudentHub.quickPanelWillOpen")
}

enum MenuBarTaskGroup: CaseIterable, Hashable {
    case unscheduled
    case planned
    case overdue

    var title: String {
        switch self {
        case .unscheduled: "Unscheduled"
        case .planned: "Planned"
        case .overdue: "Overdue"
        }
    }

    var emptyMessage: String {
        switch self {
        case .unscheduled: "Nothing waiting to be scheduled."
        case .planned: "Nothing planned."
        case .overdue: "Nothing overdue."
        }
    }
}

extension AppState {
    func menuBarPlannedDate(
        for taskID: UUID,
        calendar: Calendar = .current
    ) -> Date? {
        scheduleBlocks
            .filter { $0.linkedTaskID == taskID }
            .compactMap { block in
                calendar.date(
                    byAdding: .minute,
                    value: Int((block.startHour * 60).rounded()),
                    to: calendar.startOfDay(for: block.date)
                )
            }
            .min()
    }

    func menuBarScheduleStartMinute(
        for block: ScheduleBlock,
        on date: Date,
        calendar: Calendar = .current
    ) -> Int? {
        let minutes = Int((block.startHour * 60).rounded())
        if calendar.isDate(block.date, inSameDayAs: date) { return minutes }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)),
              calendar.isDate(block.date, inSameDayAs: nextDay),
              block.startHour < 6 else { return nil }
        return 24 * 60 + minutes
    }

    func menuBarScheduleBlocks(
        on date: Date,
        calendar: Calendar = .current
    ) -> [ScheduleBlock] {
        scheduleBlocks
            .filter { menuBarScheduleStartMinute(for: $0, on: date, calendar: calendar) != nil }
            .sorted {
                let lhs = menuBarScheduleStartMinute(for: $0, on: date, calendar: calendar) ?? .max
                let rhs = menuBarScheduleStartMinute(for: $1, on: date, calendar: calendar) ?? .max
                return lhs == rhs ? $0.title < $1.title : lhs < rhs
            }
    }

    func menuBarTasks(
        in group: MenuBarTaskGroup,
        asOf date: Date = Date(),
        calendar: Calendar = .current
    ) -> [HubTask] {
        let startOfToday = calendar.startOfDay(for: date)
        let matching = tasks.filter { task in
            guard !task.isCompleted else { return false }
            let isOverdue = task.dueDate < startOfToday
            let isPlanned = scheduleBlocks.contains { $0.linkedTaskID == task.id }
            switch group {
            case .unscheduled: return !isOverdue && !isPlanned
            case .planned: return !isOverdue && isPlanned
            case .overdue: return isOverdue
            }
        }

        guard group == .planned else { return matching.sorted { $0.dueDate < $1.dueDate } }
        return matching.sorted {
            (menuBarPlannedDate(for: $0.id, calendar: calendar) ?? .distantFuture)
                < (menuBarPlannedDate(for: $1.id, calendar: calendar) ?? .distantFuture)
        }
    }
}

struct MacMenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var selectedMinute = 0
    @State private var editingTaskID: UUID?
    @State private var draggedTaskID: UUID?

    static func snappedScheduleMinute(
        locationY: CGFloat,
        rowHeight: CGFloat
    ) -> Int {
        guard rowHeight > 0 else { return 0 }
        let minute = Int((Double(max(0, locationY) / rowHeight) * 12).rounded()) * 5
        return min(30 * 60 - 5, minute)
    }

    var body: some View {
        VStack(spacing: 0) {
            MenuBarWeekCalendar(selection: $selectedDate)

            Divider()

            MenuBarScheduleView(
                selectedDate: $selectedDate,
                selectedMinute: $selectedMinute,
                draggedTaskID: $draggedTaskID,
                onEditTask: { editingTaskID = $0 }
            )

            Divider()

            Button {
                QuickPanelController.shared.toggle()
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "command.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(HubPalette.hubAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quick Command")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Capture, search, or run a command")
                            .font(.caption)
                            .foregroundStyle(HubPalette.secondaryText)
                    }
                    Spacer()
                    Text("⌥ Space")
                        .font(.caption.monospaced())
                        .foregroundStyle(HubPalette.secondaryText)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Quick Command")

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(MenuBarTaskGroup.allCases, id: \.self) { group in
                        taskSection(group)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 360, height: 620)
        .background(Color.hubBackground)
        .onAppear(perform: focusCurrentTime)
        .sheet(isPresented: editingTaskPresented) {
            if let editingTaskID,
               appState.tasks.contains(where: { $0.id == editingTaskID }) {
                TaskInspectorSheet(taskID: editingTaskID)
                    .environmentObject(appState)
            }
        }
    }

    private var editingTaskPresented: Binding<Bool> {
        Binding(
            get: { editingTaskID != nil },
            set: { if !$0 { editingTaskID = nil } }
        )
    }

    private var plannedDate: Date {
        Calendar.current.date(
            byAdding: .minute,
            value: selectedMinute,
            to: Calendar.current.startOfDay(for: selectedDate)
        ) ?? selectedDate
    }

    private var selectedTimeLabel: String {
        let prefix = selectedMinute >= 24 * 60 ? "+1 " : ""
        return prefix + plannedDate.formatted(date: .omitted, time: .shortened)
    }

    private func taskSection(_ group: MenuBarTaskGroup) -> some View {
        let tasks = appState.menuBarTasks(in: group)

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(group.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                Spacer()
                Text("\(tasks.count)")
                    .monospacedDigit()
            }
            .foregroundStyle(HubPalette.tertiaryText)
            .padding(.horizontal, 2)

            Group {
                if tasks.isEmpty {
                    Text(group.emptyMessage)
                        .font(.callout)
                        .foregroundStyle(HubPalette.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .padding(.horizontal, 10)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                            TaskChecklistRow(
                                task: task,
                                timingLabel: group == .planned ? plannedTimeLabel(for: task) : nil
                                )
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .onTapGesture { editingTaskID = task.id }
                                .draggable(menuBarDragPayload(for: task.id)) {
                                    Color.clear.frame(width: 1, height: 1)
                                }
                                .contextMenu {
                                    Button("Edit task", systemImage: "pencil") {
                                        editingTaskID = task.id
                                    }
                                    Button("Plan at \(selectedTimeLabel)", systemImage: "calendar.badge.plus") {
                                        schedule(task)
                                    }
                                    if appState.scheduleBlocks.contains(where: { $0.linkedTaskID == task.id }) {
                                        Divider()
                                        Button("Remove all planned times", systemImage: "calendar.badge.minus") {
                                            appState.unschedule(task.id)
                                        }
                                    }
                                    Divider()
                                    Button(role: .destructive) {
                                        appState.deleteTask(task.id)
                                    } label: {
                                        Label("Delete task", systemImage: "trash")
                                    }
                                }
                                .help("Click to edit, or drag onto the schedule to plan \(task.title)")
                                .accessibilityHint("Drag onto the schedule to plan this task")
                            if index < tasks.count - 1 {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                }
            }
            .hubPanel(cornerRadius: 12)
        }
    }

    private func focusCurrentTime() {
        let now = Date()
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        selectedDate = Calendar.current.startOfDay(for: now)
        selectedMinute = min(24 * 60 - 5, ((components.hour ?? 0) * 60 + (components.minute ?? 0)) / 5 * 5)
    }

    private func schedule(_ task: HubTask) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: plannedDate)
        let hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        appState.schedule(task.id, at: hour, on: plannedDate)
    }

    private func menuBarDragPayload(for taskID: UUID) -> String {
        DispatchQueue.main.async { draggedTaskID = taskID }
        return "schedule-task:\(taskID.uuidString)"
    }

    private func plannedTimeLabel(for task: HubTask) -> String? {
        guard let date = appState.menuBarPlannedDate(for: task.id) else { return nil }
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(date) {
            day = "Today"
        } else if calendar.isDateInTomorrow(date) {
            day = "Tomorrow"
        } else {
            day = date.formatted(.dateTime.month(.abbreviated).day())
        }
        let count = appState.scheduleBlocks.filter { $0.linkedTaskID == task.id }.count
        let additionalBlocks = count > 1 ? " · \(count) blocks" : ""
        return "\(day) · \(date.formatted(date: .omitted, time: .shortened))\(additionalBlocks)"
    }
}

private struct MenuBarWeekCalendar: View {
    @Binding var selection: Date

    private var days: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: selection)?.start ?? selection
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(selection.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Today") {
                    selection = Calendar.current.startOfDay(for: Date())
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                Button {
                    changeWeek(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous week")
                Button {
                    changeWeek(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next week")
            }

            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let isToday = Calendar.current.isDateInToday(day)
                    let isSelected = Calendar.current.isDate(day, inSameDayAs: selection)
                    Button {
                        selection = Calendar.current.startOfDay(for: day)
                    } label: {
                        VStack(spacing: 3) {
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.system(size: 9, weight: .semibold))
                            Text(day.formatted(.dateTime.day()))
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        }
                        .foregroundStyle(isSelected ? Color.white : (isToday ? HubPalette.hubAccent : HubPalette.secondaryText))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(isSelected ? HubPalette.hubAccent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .accessibilityValue(isSelected ? "Selected" : (isToday ? "Today" : ""))
                }
            }
        }
        .padding(12)
    }

    private func changeWeek(by value: Int) {
        selection = Calendar.current.date(byAdding: .weekOfYear, value: value, to: selection) ?? selection
    }
}

private struct MenuBarScheduleView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedDate: Date
    @Binding var selectedMinute: Int
    @Binding var draggedTaskID: UUID?
    let onEditTask: (UUID) -> Void

    @State private var scrollRequest = 0
    @State private var dropPreviewMinute: Int?
    @State private var hoveredMinute: Int?
    @State private var acceptsDropUpdates = false

    private let rowHeight: CGFloat = 72
    private let timelineEndHour = 30

    private var blocks: [ScheduleBlock] {
        appState.menuBarScheduleBlocks(on: selectedDate)
    }

    private var plannedDate: Date {
        Calendar.current.date(
            byAdding: .minute,
            value: selectedMinute,
            to: Calendar.current.startOfDay(for: selectedDate)
        ) ?? selectedDate
    }

    private var selectedTimeLabel: String {
        let prefix = selectedMinute >= 24 * 60 ? "+1 " : ""
        return prefix + plannedDate.formatted(date: .omitted, time: .shortened)
    }

    private var openTasks: [HubTask] {
        appState.schedulableTasks().sorted { $0.dueDate < $1.dueDate }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text("Schedule")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(blocks.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(HubPalette.tertiaryText)
                Spacer()
                Button(action: focusCurrentTime) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(.plain)
                .help("Jump to now")
                Button { shiftTime(by: -5) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Five minutes earlier")
                if selectedMinute >= 24 * 60 {
                    Text("+1")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(HubPalette.hubAccent)
                }
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 76)
                Button { shiftTime(by: 5) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Five minutes later")
                assignMenu
            }

            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        scheduleDropTarget(
                            ZStack(alignment: .topLeading) {
                                hourGrid
                                currentTimeIndicator(now: context.date)
                                scheduleBlocksLayer
                                scheduleHoverIndicator
                                scheduleDropPreviewLayer
                            }
                            .frame(height: rowHeight * CGFloat(timelineEndHour))
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case let .active(location):
                                    hoveredMinute = snappedMinute(at: location.y)
                                case .ended:
                                    hoveredMinute = nil
                                }
                            }
                        )
                    }
                    .scrollIndicators(.visible)
                    .frame(height: 210)
                    .background(HubPalette.grouped)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(HubPalette.separator.opacity(0.72), lineWidth: 1)
                    }
                    .onAppear { scroll(to: selectedMinute, with: proxy, animated: false) }
                    .onChange(of: selectedMinute) { _, minute in
                        scroll(to: minute, with: proxy)
                    }
                    .onChange(of: selectedDate) { _, _ in
                        clearDropPreview()
                        hoveredMinute = nil
                        scroll(to: selectedMinute, with: proxy)
                    }
                    .onChange(of: scrollRequest) { _, _ in
                        scroll(to: selectedMinute, with: proxy)
                    }
                }
            }
        }
        .padding(12)
        .onDisappear {
            clearDropPreview()
            hoveredMinute = nil
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<timelineEndHour, id: \.self) { hour in
                HStack(spacing: 10) {
                    Text(hourLabel(hour))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(HubPalette.secondaryText)
                        .frame(width: 58, alignment: .trailing)
                    Rectangle()
                        .fill(HubPalette.separator.opacity(0.72))
                        .frame(height: 1)
                }
                .frame(height: rowHeight, alignment: .top)
                .id(hour)
            }
        }
        .padding(.horizontal, 8)
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                Text(hourLabel(timelineEndHour))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(HubPalette.secondaryText)
                    .frame(width: 58, alignment: .trailing)
                Rectangle()
                    .fill(HubPalette.separator.opacity(0.72))
                    .frame(height: 1)
            }
            .padding(.horizontal, 8)
        }
    }

    private var scheduleBlocksLayer: some View {
        GeometryReader { geometry in
            ForEach(blocks) { block in
                if let minute = appState.menuBarScheduleStartMinute(for: block, on: selectedDate) {
                    let task = block.linkedTaskID.flatMap { taskID in
                        appState.tasks.first(where: { $0.id == taskID })
                    }
                    Button {
                        if let task { onEditTask(task.id) }
                    } label: {
                        ScheduleBlockView(block: block, isCompleted: task?.isCompleted == true)
                    }
                    .buttonStyle(.plain)
                    .frame(width: max(1, geometry.size.width - 82))
                    .frame(height: blockHeight(block.duration))
                    .clipped()
                    .offset(x: 72, y: CGFloat(minute) / 60 * rowHeight)
                    .contextMenu {
                        if let task {
                            Button("Edit task", systemImage: "pencil") { onEditTask(task.id) }
                            Button(task.isCompleted ? "Mark incomplete" : "Complete", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark") {
                                appState.toggleComplete(task.id)
                            }
                            Divider()
                        }
                        Button("Remove this time", systemImage: "calendar.badge.minus") {
                            appState.deleteScheduleBlock(block.id)
                        }
                        if let task {
                            Divider()
                            Button(role: .destructive) {
                                appState.deleteTask(task.id)
                            } label: {
                                Label("Delete task", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func currentTimeIndicator(now: Date) -> some View {
        if let minute = visualMinute(for: now) {
            HStack(spacing: 7) {
                Text(timeLabel(for: minute))
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(HubPalette.red, in: Capsule())
                Rectangle()
                    .fill(HubPalette.red)
                    .frame(height: 1)
            }
            .padding(.horizontal, 8)
            .offset(y: CGFloat(minute) / 60 * rowHeight - 9)
            .allowsHitTesting(false)
            .accessibilityLabel("Current time, \(now.formatted(date: .omitted, time: .shortened))")
        }
    }

    @ViewBuilder
    private var scheduleDropPreviewLayer: some View {
        if let minute = dropPreviewMinute {
            GeometryReader { geometry in
                let task = draggedTaskID.flatMap { taskID in
                    appState.tasks.first(where: { $0.id == taskID })
                }
                let duration = task.map(AppState.taskScheduleDuration) ?? 1

                Group {
                    if let task {
                        ScheduleBlockView(
                            block: ScheduleBlock(
                                title: task.title,
                                subtitle: task.course.title,
                                course: task.course,
                                startHour: Double(minute % (24 * 60)) / 60,
                                duration: duration,
                                date: plannedDate(for: minute),
                                linkedTaskID: task.id
                            )
                        )
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(HubPalette.hubAccent.opacity(0.12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(HubPalette.hubAccent.opacity(0.72), lineWidth: 1)
                            }
                    }
                }
                .frame(width: max(1, geometry.size.width - 82))
                .frame(height: blockHeight(duration))
                .clipped()
                .opacity(0.82)
                .offset(x: 72, y: CGFloat(minute) / 60 * rowHeight)

                Text(timeLabel(for: minute))
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(HubPalette.hubAccent, in: Capsule())
                    .offset(x: 8, y: max(0, CGFloat(minute) / 60 * rowHeight - 9))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var scheduleHoverIndicator: some View {
        if dropPreviewMinute == nil, let minute = hoveredMinute {
            HStack(spacing: 7) {
                Text(timeLabel(for: minute))
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(HubPalette.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(HubPalette.selected, in: Capsule())
                Rectangle()
                    .fill(HubPalette.separator)
                    .frame(height: 1)
            }
            .padding(.horizontal, 8)
            .offset(y: CGFloat(minute) / 60 * rowHeight - 9)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { plannedDate },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                let dayOffset = selectedMinute >= 24 * 60 ? 24 * 60 : 0
                selectedMinute = min(30 * 60 - 5, dayOffset + (components.hour ?? 0) * 60 + (components.minute ?? 0))
            }
        )
    }

    private var assignMenu: some View {
        Menu {
            Button("New task at \(selectedTimeLabel)", systemImage: "plus") {
                let task = appState.addTask(
                    title: "New task",
                    course: appState.defaultSpace,
                    dueDate: plannedDate
                )
                schedule(task)
                onEditTask(task.id)
            }
            Divider()
            if openTasks.isEmpty {
                Text("No open tasks")
            } else {
                ForEach(openTasks) { task in
                    Button {
                        schedule(task)
                    } label: {
                        Text("\(task.title) — \(task.course.title)")
                    }
                }
            }
        } label: {
            Label("Assign", systemImage: "calendar.badge.plus")
                .font(.system(size: 11, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Assign a task at \(selectedTimeLabel)")
    }

    private func focusCurrentTime() {
        let now = Date()
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        selectedDate = Calendar.current.startOfDay(for: now)
        selectedMinute = min(24 * 60 - 5, ((components.hour ?? 0) * 60 + (components.minute ?? 0)) / 5 * 5)
        scrollRequest += 1
    }

    private func shiftTime(by minutes: Int) {
        selectedMinute = min(30 * 60 - 5, max(0, selectedMinute + minutes))
    }

    private func schedule(_ task: HubTask) {
        schedule(task.id, at: selectedMinute, on: selectedDate)
    }

    private func schedule(_ taskID: UUID, at minute: Int, on date: Date) {
        guard appState.tasks.contains(where: { $0.id == taskID }) else { return }
        let calendar = Calendar.current
        let plannedDate = calendar.date(
            byAdding: .minute,
            value: minute,
            to: calendar.startOfDay(for: date)
        ) ?? date
        let components = calendar.dateComponents([.hour, .minute], from: plannedDate)
        let hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        appState.schedule(taskID, at: hour, on: plannedDate)
        selectedMinute = minute
    }

    private func scheduleDroppedTask(_ payload: String, at minute: Int) {
        clearDropPreview()
        guard let taskID = scheduleTaskID(from: payload) else { return }
        schedule(taskID, at: minute, on: selectedDate)
        draggedTaskID = nil
    }

    private func scheduleTaskID(from payload: String) -> UUID? {
        let prefix = "schedule-task:"
        if payload.hasPrefix(prefix) {
            return UUID(uuidString: String(payload.dropFirst(prefix.count)))
        }
        return UUID(uuidString: payload)
    }

    private func plannedDate(for minute: Int) -> Date {
        Calendar.current.date(
            byAdding: .minute,
            value: minute,
            to: Calendar.current.startOfDay(for: selectedDate)
        ) ?? selectedDate
    }

    private func blockHeight(_ duration: Double) -> CGFloat {
        max(1, CGFloat(duration) * rowHeight)
    }

    private func visualMinute(for date: Date) -> Int? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if calendar.isDate(date, inSameDayAs: selectedDate) { return minutes }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: selectedDate),
              calendar.isDate(date, inSameDayAs: nextDay),
              (components.hour ?? 0) < 6 else { return nil }
        return 24 * 60 + minutes
    }

    private func timeLabel(for minute: Int) -> String {
        let date = Calendar.current.date(
            byAdding: .minute,
            value: minute,
            to: Calendar.current.startOfDay(for: selectedDate)
        ) ?? selectedDate
        let prefix = minute >= 24 * 60 ? "+1 " : ""
        return prefix + date.formatted(date: .omitted, time: .shortened)
    }

    private func hourLabel(_ hour: Int) -> String {
        let clockHour = hour % 24
        let suffix = clockHour < 12 ? "AM" : "PM"
        let display = clockHour == 0 || clockHour == 12 ? 12 : clockHour % 12
        return "\(hour >= 24 ? "+1 " : "")\(display) \(suffix)"
    }

    private func scroll(
        to minute: Int,
        with proxy: ScrollViewProxy,
        animated: Bool = true
    ) {
        let target = min(timelineEndHour - 1, max(0, minute / 60))
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            } else {
                proxy.scrollTo(target, anchor: .center)
            }
        }
    }

    private func clearDropPreview() {
        acceptsDropUpdates = false
        dropPreviewMinute = nil
        draggedTaskID = nil
    }

    @ViewBuilder
    private func scheduleDropTarget<Content: View>(_ content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .dropDestination(for: String.self) { items, session in
                    let minute = snappedMinute(at: session.location.y)
                    clearDropPreview()
                    guard let payload = items.first else { return }
                    scheduleDroppedTask(payload, at: minute)
                }
                .onDropSessionUpdated { session in
                    switch session.phase {
                    case .entering, .active:
                        dropPreviewMinute = snappedMinute(at: session.location.y)
                    case .exiting, .ended(_), .dataTransferCompleted:
                        clearDropPreview()
                    @unknown default:
                        clearDropPreview()
                    }
                }
                .dropConfiguration { _ in DropConfiguration(operation: .move) }
        } else {
            content.onDrop(
                of: [UTType.plainText],
                delegate: MenuBarScheduleDropDelegate(
                    previewIsActive: { acceptsDropUpdates },
                    setPreviewActive: { acceptsDropUpdates = $0 },
                    minuteAtLocation: { snappedMinute(at: $0.y) },
                    previewMinuteChanged: { dropPreviewMinute = $0 },
                    dropPayload: { scheduleDroppedTask($0, at: $1) }
                )
            )
        }
    }

    private func snappedMinute(at y: CGFloat) -> Int {
        MacMenuBarView.snappedScheduleMinute(locationY: y, rowHeight: rowHeight)
    }
}

private struct MenuBarScheduleDropDelegate: DropDelegate {
    let previewIsActive: () -> Bool
    let setPreviewActive: (Bool) -> Void
    let minuteAtLocation: (CGPoint) -> Int
    let previewMinuteChanged: (Int?) -> Void
    let dropPayload: (String, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        let isValid = info.hasItemsConforming(to: [UTType.plainText])
        if !isValid { clearPreview() }
        return isValid
    }

    func dropEntered(info: DropInfo) {
        setPreviewActive(true)
        previewMinuteChanged(minuteAtLocation(info.location))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard previewIsActive() else { return DropProposal(operation: .copy) }
        previewMinuteChanged(minuteAtLocation(info.location))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        clearPreview()
    }

    func performDrop(info: DropInfo) -> Bool {
        let minute = minuteAtLocation(info.location)
        clearPreview()
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else { return false }
        _ = provider.loadTransferable(type: String.self) { result in
            guard case let .success(payload) = result else { return }
            DispatchQueue.main.async { dropPayload(payload, minute) }
        }
        return true
    }

    private func clearPreview() {
        setPreviewActive(false)
        previewMinuteChanged(nil)
    }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) {
            DispatchQueue.main.async {
                QuickPanelController.shared.toggle()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey = nil
    }
}

@MainActor
final class QuickPanelController {
    static let shared = QuickPanelController(appState: .shared)

    private let panel: NSPanel

    private init(appState: AppState) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 500),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.panel = panel

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let root = QuickCommandView(onDismiss: { [weak panel] in
            panel?.orderOut(nil)
        })
        .environmentObject(appState)

        panel.contentView = NSHostingView(rootView: root)
        panel.center()
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            NotificationCenter.default.post(name: .quickPanelWillOpen, object: nil)
            panel.center()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }
}

final class GlobalHotKey: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            owner.action()
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x53544842), id: 1)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}
#endif

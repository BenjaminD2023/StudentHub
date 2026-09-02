import SwiftUI
import UniformTypeIdentifiers

/// Today (home page). Calendar-centric layout: month grid at the
/// top, week strip + day timeline below, and quick action cards on
/// the side. Designed to be the user's daily launchpad.
struct DayTimelineView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentDay = Calendar.current.startOfDay(for: Date())
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var scheduleDropPreviewHour: Double?
    @State private var hoveredScheduleHour: Double?
    @State private var draggedScheduleTaskID: UUID?
    @State private var draggedScheduleBlockID: UUID?
    @State private var isUnscheduleDropTargeted = false

    private let rowHeight: CGFloat = 56
    private static let timelineEndHour = 30.0
    private static let nextDayCutoffHour = 6.0

    private var today: Date { currentDay }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var timelineBlocks: [TimelineBlock] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: selectedDate)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        return appState.scheduleBlocks.compactMap { block in
            if calendar.isDate(block.date, inSameDayAs: day) {
                return TimelineBlock(block: block, displayStartHour: block.startHour)
            }
            if calendar.isDate(block.date, inSameDayAs: nextDay), block.startHour < Self.nextDayCutoffHour {
                return TimelineBlock(block: block, displayStartHour: 24 + block.startHour)
            }
            return nil
        }
        .sorted { $0.displayStartHour < $1.displayStartHour }
    }

    private var tasksDueToday: [HubTask] {
        let calendar = Calendar.current
        return appState.tasks
            .filter { !$0.isCompleted && calendar.isDateInToday($0.dueDate) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var overdueTasks: [HubTask] {
        appState.tasks
            .filter { $0.isOverdue }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var unscheduledTasks: [HubTask] {
        let scheduledTaskIDs = Set(appState.scheduleBlocks.compactMap(\.linkedTaskID))
        return appState.tasks
            .filter { !$0.isCompleted && !scheduledTaskIDs.contains($0.id) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var plannedBlocks: [ScheduleBlock] {
        Self.plannedScheduleBlocks(tasks: appState.tasks, scheduleBlocks: appState.scheduleBlocks)
    }

    static func plannedScheduleBlocks(tasks: [HubTask], scheduleBlocks: [ScheduleBlock]) -> [ScheduleBlock] {
        let openTaskIDs = Set(tasks.filter { !$0.isCompleted }.map(\.id))
        return scheduleBlocks
            .filter { block in
                block.linkedTaskID.map(openTaskIDs.contains) == true
            }
            .sorted { Self.scheduledDate(for: $0) < Self.scheduledDate(for: $1) }
    }

    private var positionedBlocks: [PositionedBlock] {
        var groups: [[TimelineBlock]] = []
        for timelineBlock in timelineBlocks {
            if var last = groups.last, let lastBlock = last.last,
               abs(timelineBlock.displayStartHour - lastBlock.displayStartHour) < 0.001 {
                last.append(timelineBlock)
                groups[groups.count - 1] = last
            } else {
                groups.append([timelineBlock])
            }
        }
        var result: [PositionedBlock] = []
        for group in groups {
            let count = group.count
            for (index, timelineBlock) in group.enumerated() {
                result.append(PositionedBlock(timelineBlock: timelineBlock, column: index, columnCount: count))
            }
        }
        return result
    }

    private struct TimelineBlock: Identifiable {
        let block: ScheduleBlock
        let displayStartHour: Double
        var id: UUID { block.id }
    }

    private struct PositionedBlock: Identifiable {
        let timelineBlock: TimelineBlock
        let column: Int
        let columnCount: Int
        var block: ScheduleBlock { timelineBlock.block }
        var displayStartHour: Double { timelineBlock.displayStartHour }
        var id: UUID { block.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            homeHeader
            homeStatRow
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    dayTimelineColumn
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                    rightRailScroll
                        .frame(width: 300)
                }
                .frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 12) {
                    compactTaskTray
                    dayTimelineColumn
                        .frame(minHeight: 240, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HubPalette.background)
        .onAppear { refreshCurrentDay(forceSelection: true) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshCurrentDay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            refreshCurrentDay()
        }
    }

    // MARK: - Header

    private var homeHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                homeTitle.fixedSize(horizontal: true, vertical: false)
                Spacer()
                homeHeaderActions.fixedSize()
            }

            VStack(alignment: .leading, spacing: 10) {
                homeTitle
                homeHeaderActions
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var homeTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.system(size: 12, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(today.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 32, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var homeHeaderActions: some View {
        HStack(spacing: 10) {
            Button {
                let task = appState.addTask(title: "New task")
                appState.selectedTaskID = task.id
            } label: { Label("New task", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
            Button {
                let block = ScheduleBlock(
                    title: "Focus block",
                    subtitle: "Chemistry",
                    course: .general,
                    startHour: 9,
                    duration: 1,
                    date: today
                )
                appState.scheduleBlocks.append(block)
                appState.persist()
            } label: { Label("Add block", systemImage: "calendar.badge.plus") }
                .buttonStyle(.bordered)
            Menu {
                Button("Today") { selectedDate = today }
                Divider()
                Button("Open calendar") { appState.navigate(to: .calendar) }
                Button("Open Command Hub") { appState.isCommandHubVisible = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 4..<12: return "GOOD MORNING"
        case 12..<18: return "GOOD AFTERNOON"
        case 18..<22: return "GOOD EVENING"
        default: return "GOOD NIGHT"
        }
    }

    // MARK: - Stat row

    private var homeStatRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                homeStatTiles
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 140), spacing: 12), count: 3),
                spacing: 12
            ) {
                homeStatTiles
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(minimum: 140), spacing: 12), count: 2),
                spacing: 12
            ) {
                homeStatTiles
            }

            VStack(spacing: 12) {
                homeStatTiles
            }
        }
    }

    @ViewBuilder
    private var homeStatTiles: some View {
        statTile(
            icon: "checkmark.square.fill",
            tint: HubPalette.hubAccent,
            value: "\(tasksDueToday.count)",
            label: "Due today"
        )
        statTile(
            icon: "exclamationmark.triangle.fill",
            tint: HubPalette.red,
            value: "\(overdueTasks.count)",
            label: "Overdue"
        )
        statTile(
            icon: "clock.fill",
            tint: HubPalette.yellow,
            value: "\(timelineBlocks.count)",
            label: "On calendar"
        )
        statTile(
            icon: "hourglass",
            tint: HubPalette.success,
            value: appState.plannedWorkload(on: selectedDate).studyDurationLabel,
            label: "Workload"
        )
        statTile(
            icon: "doc.text.fill",
            tint: Color(red: 0.55, green: 0.4, blue: 0.85),
            value: "\(appState.captures.count)",
            label: "Captures"
        )
        statTile(
            icon: "folder.fill",
            tint: HubPalette.success,
            value: "\(appState.tasks.filter { !$0.isCompleted }.count)",
            label: "All open"
        )
    }

    private func statTile(icon: String, tint: Color, value: String, label: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 140, maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(HubPalette.grouped)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HubPalette.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Day timeline

    private var dayTimelineColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                HStack(spacing: 10) {
                    Label("Drag tasks onto a time", systemImage: "hand.draw")
                    if !timelineBlocks.isEmpty {
                        Text("\(timelineBlocks.count) blocks")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            weekStrip

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    scheduleDropTarget(
                        ZStack(alignment: .topLeading) {
                            hourGrid
                            currentTimeIndicator
                            scheduleBlocksLayer
                            scheduleHoverIndicator
                            scheduleDropPreviewLayer
                        }
                        .frame(height: rowHeight * Self.timelineEndHour)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case let .active(location):
                                hoveredScheduleHour = snappedScheduleHour(for: location.y)
                            case .ended:
                                hoveredScheduleHour = nil
                            }
                        }
                    )
                }
                .background(HubPalette.grouped)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(HubPalette.separator, lineWidth: 0.5)
                }
                .onAppear { scrollSchedule(proxy) }
                .onChange(of: selectedDate) { _, _ in
                    clearScheduleDropPreview()
                    scrollSchedule(proxy)
                }
                .onDisappear {
                    clearScheduleDropPreview()
                    hoveredScheduleHour = nil
                }
            }
            .layoutPriority(1)
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(weekDays, id: \.self) { day in
                let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                let isToday = Calendar.current.isDate(day, inSameDayAs: today)
                Button {
                    selectedDate = day
                } label: {
                    VStack(spacing: 3) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(.system(size: 16, weight: isSelected || isToday ? .bold : .semibold))
                    }
                    .foregroundStyle(isSelected ? .white : HubPalette.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? HubPalette.hubAccent : (isToday ? HubPalette.hubAccent.opacity(0.12) : Color.clear))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<Int(Self.timelineEndHour), id: \.self) { hour in
                HStack(spacing: 12) {
                    Text(formatHour(hour))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    Rectangle()
                        .fill(HubPalette.separator.opacity(0.6))
                        .frame(height: 1)
                }
                .frame(height: rowHeight, alignment: .top)
                .id(hour)
            }
        }
        .padding(.horizontal, 14)
        .overlay(alignment: .bottom) {
            HStack(spacing: 12) {
                Text(formatHour(Int(Self.timelineEndHour)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
                Rectangle()
                    .fill(HubPalette.separator.opacity(0.6))
                    .frame(height: 1)
            }
            .padding(.horizontal, 14)
        }
    }

    private var scheduleBlocksLayer: some View {
        GeometryReader { geometry in
            let leftInset: CGFloat = 78
            let rightInset: CGFloat = 14
            let columnGap: CGFloat = 6
            ForEach(positionedBlocks) { positioned in
                let isCompleted = positioned.block.linkedTaskID.flatMap { taskID in
                    appState.tasks.first(where: { $0.id == taskID })?.isCompleted
                } ?? false
                let availableWidth = max(1, geometry.size.width - leftInset - rightInset)
                let totalGaps = columnGap * CGFloat(max(0, positioned.columnCount - 1))
                let blockWidth = (availableWidth - totalGaps) / CGFloat(positioned.columnCount)
                Group {
                    if let taskID = positioned.block.linkedTaskID {
                        ScheduleBlockView(block: positioned.block, isCompleted: isCompleted)
                            .contextMenu {
                                Button {
                                    editTask(taskID)
                                } label: {
                                    Label("Edit task", systemImage: "pencil")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    appState.deleteTask(taskID)
                                } label: {
                                    Label("Delete task", systemImage: "trash")
                                }
                            }
                            .onDrag {
                                scheduleDragProvider(for: taskID, blockID: positioned.block.id)
                            } preview: {
                                Color.clear.frame(width: 1, height: 1)
                            }
                    } else {
                        ScheduleBlockView(block: positioned.block, isCompleted: isCompleted)
                    }
                }
                    .frame(width: blockWidth)
                    .frame(height: scheduleBlockHeight(for: positioned.block.duration))
                    .clipped()
                    .opacity(
                        scheduleDropPreviewHour != nil && positioned.block.id == draggedScheduleBlockID
                            ? 0
                            : 1
                    )
                    .offset(
                        x: leftInset + CGFloat(positioned.column) * (blockWidth + columnGap),
                        y: positioned.displayStartHour * rowHeight + 7
                    )
            }
        }
    }

    @ViewBuilder
    private var scheduleDropPreviewLayer: some View {
        if let hour = scheduleDropPreviewHour {
            GeometryReader { geometry in
                let task = draggedScheduleTaskID.flatMap { taskID in
                    appState.tasks.first(where: { $0.id == taskID })
                }
                let duration = draggedScheduleBlockID.flatMap { blockID in
                    appState.scheduleBlocks.first(where: { $0.id == blockID })?.duration
                } ?? task.map(AppState.taskScheduleDuration) ?? 1
                let target = scheduleTarget(for: hour)
                let leftInset: CGFloat = 78

                Group {
                    if let task {
                        ScheduleBlockView(
                            block: ScheduleBlock(
                                title: task.title,
                                subtitle: task.course.title,
                                course: task.course,
                                startHour: target.hour,
                                duration: duration,
                                date: target.date,
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
                    .frame(width: max(1, geometry.size.width - leftInset - 14))
                    .frame(height: scheduleBlockHeight(for: duration))
                    .clipped()
                    .offset(x: leftInset, y: hour * rowHeight + 7)

                Text(formatTime(hour))
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(HubPalette.hubAccent, in: Capsule())
                    .offset(x: 8, y: max(0, hour * rowHeight - 10))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var scheduleHoverIndicator: some View {
        if scheduleDropPreviewHour == nil, let hour = hoveredScheduleHour {
            HStack(spacing: 8) {
                Text(formatTime(hour))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(HubPalette.secondaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(HubPalette.selected, in: Capsule())
                Rectangle()
                    .fill(HubPalette.separator)
                    .frame(height: 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .offset(y: CGFloat(hour) * rowHeight - 9)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var currentTimeIndicator: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            if let hour = timelineHour(for: context.date) {
                HStack(spacing: 8) {
                    Text("\(hour >= 24 ? "+1 " : "")\(context.date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(HubPalette.red, in: Capsule())
                    Rectangle()
                        .fill(HubPalette.red)
                        .frame(height: 1)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .offset(y: CGFloat(hour) * rowHeight - 9)
                .allowsHitTesting(false)
                .accessibilityLabel("Current time, \(context.date.formatted(date: .omitted, time: .shortened))")
            }
        }
    }

    // MARK: - Right rail

    private var rightRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            railCard(title: "Unscheduled", count: unscheduledTasks.count) {
                railTaskList(unscheduledTasks, emptyMessage: "Every open task is on the calendar.")
            }

            railCard(title: "Planned", count: plannedBlocks.count) {
                plannedTaskList
            }

            railCard(title: "Overdue", count: overdueTasks.count) {
                railTaskList(overdueTasks, emptyMessage: "Nothing overdue.")
            }

            if !appState.captures.isEmpty {
                railCard(title: "Scratchpad", count: appState.captures.count) {
                    ForEach(appState.captures.prefix(3)) { capture in
                        ScratchpadEditRow(capture: capture)
                        if capture.id != appState.captures.prefix(3).last?.id { Divider() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func railTaskList(_ tasks: [HubTask], emptyMessage: String) -> some View {
        if tasks.isEmpty {
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        } else {
            let visibleTasks = Array(tasks.prefix(12))
            ForEach(visibleTasks) { task in
                railTaskRow(task)
                if task.id != visibleTasks.last?.id { Divider() }
            }
        }
    }

    @ViewBuilder
    private var plannedTaskList: some View {
        if plannedBlocks.isEmpty {
            Text("No tasks are planned yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        } else {
            ForEach(plannedBlocks) { block in
                if let taskID = block.linkedTaskID,
                   let task = appState.tasks.first(where: { $0.id == taskID }) {
                    railTaskRow(
                        task,
                        plannedDate: Self.scheduledDate(for: block),
                        scheduleBlockID: block.id
                    )
                    if block.id != plannedBlocks.last?.id { Divider() }
                }
            }
        }
    }

    private var rightRailScroll: some View {
        unscheduleDropTarget(
            ScrollView(.vertical) {
                rightRail
                    .padding(.trailing, 4)
            }
            .scrollIndicators(.hidden)
        )
    }

    private var compactTaskTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Unscheduled".uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(unscheduledTasks.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if unscheduledTasks.isEmpty {
                Text("Every open task is on the calendar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(unscheduledTasks.prefix(12)) { task in
                            railTaskRow(task)
                                .padding(.horizontal, 10)
                                .frame(width: 250)
                                .background(HubPalette.grouped)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(HubPalette.separator, lineWidth: 0.5)
                                }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func railCard<Content: View>(title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            VStack(spacing: 0) {
                content()
            }
            .padding(10)
            .background(HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(HubPalette.separator, lineWidth: 0.5)
            )
        }
    }

    private func railTaskRow(
        _ task: HubTask,
        plannedDate: Date? = nil,
        scheduleBlockID: UUID? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Button { appState.toggleComplete(task.id) } label: {
                Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundStyle(task.course.accent)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    if let plannedDate {
                        Text(plannedTimeLabel(for: plannedDate))
                            .fontWeight(.semibold)
                            .foregroundStyle(HubPalette.hubAccent)
                            .monospacedDigit()
                            .fixedSize(horizontal: true, vertical: false)
                        Text("· \(task.course.title)")
                    } else {
                        Text("\(task.course.title) · \(task.dueDate.formatted(.relative(presentation: .named)))")
                    }
                    if let estimate = task.estimatedDurationLabel {
                        Text("· \(estimate)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if let scheduleBlockID {
                Button {
                    appState.deleteScheduleBlock(scheduleBlockID)
                } label: {
                    Image(systemName: "calendar.badge.minus")
                        .foregroundStyle(HubPalette.hubAccent)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Remove this time block")
                .accessibilityLabel("Remove this time block for \(task.title)")
            } else {
                Button {
                    appState.schedule(task.id, at: quickScheduleHour, on: selectedDate)
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundStyle(HubPalette.hubAccent)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Schedule at \(formatTime(quickScheduleHour)); drag to choose a time")
                .accessibilityLabel("Schedule \(task.title) at \(formatTime(quickScheduleHour))")
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onDrag {
            scheduleDragProvider(for: task.id, blockID: scheduleBlockID)
        } preview: {
            Color.clear.frame(width: 1, height: 1)
        }
        .contextMenu {
            Button {
                editTask(task.id)
            } label: {
                Label("Edit task", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                appState.deleteTask(task.id)
            } label: {
                Label("Delete task", systemImage: "trash")
            }
        }
        .accessibilityHint("Drag onto the timetable to choose a time")
    }

    // MARK: - Helpers

    private func editTask(_ taskID: UUID) {
        guard appState.tasks.contains(where: { $0.id == taskID }) else { return }
        appState.selectedTaskID = taskID
        appState.navigate(to: .tasks)
    }

    private static func scheduledDate(for block: ScheduleBlock) -> Date {
        let day = Calendar.current.startOfDay(for: block.date)
        let minutes = Int((block.startHour * 60).rounded())
        return Calendar.current.date(byAdding: .minute, value: minutes, to: day) ?? day
    }

    private func plannedTimeLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(date) {
            day = "Today"
        } else if calendar.isDateInTomorrow(date) {
            day = "Tomorrow"
        } else {
            day = date.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(day), \(date.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder
    private func scheduleDropTarget<Content: View>(_ content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 26.0, *) {
            content
                .dropDestination(for: String.self) { items, session in
                    let hour = snappedScheduleHour(for: session.location.y)
                    clearScheduleDropPreview()
                    guard let payload = items.first else { return }
                    scheduleDroppedTask(payload, at: hour)
                }
                .onDropSessionUpdated { session in
                    switch session.phase {
                    case .entering, .active:
                        scheduleDropPreviewHour = snappedScheduleHour(for: session.location.y)
                    case .exiting, .ended(_), .dataTransferCompleted:
                        clearScheduleDropPreview()
                    @unknown default:
                        clearScheduleDropPreview()
                    }
                }
                .dropConfiguration { _ in DropConfiguration(operation: .move) }
        } else {
            legacyScheduleDropTarget(content)
        }
        #else
        legacyScheduleDropTarget(content)
        #endif
    }

    private func legacyScheduleDropTarget<Content: View>(_ content: Content) -> some View {
        content.onDrop(
            of: [UTType.plainText],
            delegate: ScheduleDropDelegate(
                hourAtLocation: { snappedScheduleHour(for: $0.y) },
                previewHourChanged: { scheduleDropPreviewHour = $0 },
                dropPayload: { payload, hour in
                    scheduleDroppedTask(payload, at: hour)
                    clearScheduleDropPreview()
                }
            )
        )
    }

    private func unscheduleDropTarget<Content: View>(_ content: Content) -> some View {
        content
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.first,
                      let blockID = scheduleBlockID(from: payload),
                      appState.scheduleBlocks.contains(where: { $0.id == blockID }) else { return false }
                appState.deleteScheduleBlock(blockID)
                clearScheduleDropPreview()
                return true
            } isTargeted: { targeted in
                withAnimation(.easeOut(duration: 0.12)) {
                    isUnscheduleDropTargeted = targeted
                }
            }
            .overlay {
                if isUnscheduleDropTargeted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(HubPalette.hubAccent.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(HubPalette.hubAccent, lineWidth: 2)
                        }
                        .overlay {
                            Label("Drop to unschedule", systemImage: "calendar.badge.minus")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(HubPalette.hubAccent)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 34)
                                .background(HubPalette.grouped, in: Capsule())
                        }
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
    }

    private func formatHour(_ hour: Int) -> String {
        let clockHour = hour % 24
        let suffix = clockHour < 12 ? "AM" : "PM"
        let display = clockHour == 0 || clockHour == 12 ? 12 : clockHour % 12
        return "\(hour >= 24 ? "+1 " : "")\(display) \(suffix)"
    }

    private func formatTime(_ hour: Double) -> String {
        let totalMinutes = Int((hour * 60).rounded())
        let start = Calendar.current.startOfDay(for: selectedDate)
        let date = Calendar.current.date(byAdding: .minute, value: totalMinutes, to: start) ?? start
        return "\(hour >= 24 ? "+1 " : "")\(date.formatted(date: .omitted, time: .shortened))"
    }

    private var quickScheduleHour: Double {
        guard Calendar.current.isDateInToday(selectedDate) else { return 16 }
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        return min(23.75, (hour * 4).rounded(.up) / 4)
    }

    private func scheduleDragProvider(for taskID: UUID, blockID: UUID? = nil) -> NSItemProvider {
        DispatchQueue.main.async {
            draggedScheduleTaskID = taskID
            draggedScheduleBlockID = blockID
        }
        let payload = blockID.map { "schedule-block:\($0.uuidString)" }
            ?? "schedule-task:\(taskID.uuidString)"
        return NSItemProvider(object: payload as NSString)
    }

    private func snappedScheduleHour(for y: CGFloat) -> Double {
        Self.snappedScheduleHour(for: y, rowHeight: rowHeight)
    }

    private func scheduleBlockHeight(for duration: Double) -> CGFloat {
        max(1, CGFloat(duration) * rowHeight)
    }

    private func refreshCurrentDay(now: Date = Date(), forceSelection: Bool = false) {
        let calendar = Calendar.current
        let newDay = calendar.startOfDay(for: now)
        selectedDate = Self.refreshedSelection(
            selectedDate,
            from: currentDay,
            to: newDay,
            force: forceSelection,
            calendar: calendar
        )
        currentDay = newDay
    }

    static func refreshedSelection(
        _ selectedDate: Date,
        from currentDay: Date,
        to newDay: Date,
        force: Bool,
        calendar: Calendar
    ) -> Date {
        force || calendar.isDate(selectedDate, inSameDayAs: currentDay) ? newDay : selectedDate
    }

    static func snappedScheduleHour(for y: CGFloat, rowHeight: CGFloat) -> Double {
        guard rowHeight > 0 else { return 0 }
        let slotsPerHour = 12.0
        let rawHour = Double(max(0, y) / rowHeight)
        return min(Self.timelineEndHour - 1 / slotsPerHour, (rawHour * slotsPerHour).rounded() / slotsPerHour)
    }

    private func scheduleDroppedTask(_ payload: String, at hour: Double) {
        let target = scheduleTarget(for: hour)
        if let blockID = scheduleBlockID(from: payload) {
            appState.moveScheduleBlock(blockID, to: target.hour, on: target.date)
            return
        }
        guard let taskID = scheduleTaskID(from: payload),
              appState.tasks.contains(where: { $0.id == taskID }) else { return }
        appState.schedule(taskID, at: target.hour, on: target.date)
    }

    private func scheduleBlockID(from payload: String) -> UUID? {
        guard payload.hasPrefix("schedule-block:") else { return nil }
        return UUID(uuidString: String(payload.dropFirst("schedule-block:".count)))
    }

    private func scheduleTaskID(from payload: String) -> UUID? {
        if payload.hasPrefix("schedule-task:") {
            return UUID(uuidString: String(payload.dropFirst("schedule-task:".count)))
        }
        return UUID(uuidString: payload)
    }

    private func scheduleTarget(for displayHour: Double) -> (date: Date, hour: Double) {
        let day = Calendar.current.startOfDay(for: selectedDate)
        guard displayHour >= 24 else { return (day, displayHour) }
        return (Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day, displayHour - 24)
    }

    private func timelineHour(for date: Date) -> Double? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        if calendar.isDate(date, inSameDayAs: selectedDate) { return hour }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: selectedDate)) ?? selectedDate
        return calendar.isDate(date, inSameDayAs: nextDay) && hour < Self.nextDayCutoffHour ? 24 + hour : nil
    }

    private func clearScheduleDropPreview() {
        scheduleDropPreviewHour = nil
        draggedScheduleTaskID = nil
        draggedScheduleBlockID = nil
    }

    private func scrollSchedule(_ proxy: ScrollViewProxy) {
        let hour = Int(timelineHour(for: Date()) ?? 8)
        DispatchQueue.main.async {
            proxy.scrollTo(hour, anchor: .center)
        }
    }
}

private struct ScheduleDropDelegate: DropDelegate {
    let hourAtLocation: (CGPoint) -> Double
    let previewHourChanged: (Double?) -> Void
    let dropPayload: (String, Double) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        let isValid = info.hasItemsConforming(to: [UTType.plainText])
        if !isValid { previewHourChanged(nil) }
        return isValid
    }

    func dropEntered(info: DropInfo) {
        previewHourChanged(hourAtLocation(info.location))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        previewHourChanged(hourAtLocation(info.location))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        previewHourChanged(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let hour = hourAtLocation(info.location)
        previewHourChanged(nil)
        guard let provider = info.itemProviders(for: [UTType.plainText]).first else { return false }
        _ = provider.loadTransferable(type: String.self) { result in
            guard case let .success(payload) = result else { return }
            DispatchQueue.main.async { dropPayload(payload, hour) }
        }
        return true
    }
}

private struct ScratchpadEditRow: View {
    @EnvironmentObject private var appState: AppState
    let capture: WhiteboardCapture

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField("Capture", text: $draft, axis: .vertical)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HubPalette.primaryText)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($isFocused)
                .onSubmit(commit)
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
                .onChange(of: capture.text) { _, newValue in
                    if !isFocused { draft = newValue }
                }
                .accessibilityLabel("Scratchpad note")
                .accessibilityHint("Edit this capture")
            Text(capture.createdAt.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .onAppear { draft = capture.text }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            draft = capture.text
            return
        }
        appState.updateCapture(capture.id, text: trimmed)
        draft = trimmed
    }
}

struct ScheduleBlockView: View {
    let block: ScheduleBlock
    var isCompleted = false

    private var isCompact: Bool { block.duration < 0.75 }

    var body: some View {
        HStack(spacing: isCompact ? 6 : 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(block.course.accent)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: isCompact ? 0 : 2) {
                Text(block.title)
                    .font(.system(size: isCompact ? 9 : 11, weight: .bold))
                    .strikethrough(isCompleted)
                    .lineLimit(1)
                if !isCompact {
                    Text(block.subtitle)
                        .font(.system(size: 9))
                        .lineLimit(1)
                }
            }
            Spacer()
            if block.linkedTaskID != nil && !isCompact {
                Image(systemName: "link")
                    .font(.system(size: 9))
            }
        }
        .padding(.horizontal, isCompact ? 6 : 9)
        .padding(.vertical, isCompact ? 1 : 5)
        .background(block.course.accent.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(block.course.accent.opacity(0.65), lineWidth: 1)
        }
    }
}

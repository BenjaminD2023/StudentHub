import SwiftUI

/// Today (home page). Calendar-centric layout: month grid at the
/// top, week strip + day timeline below, and quick action cards on
/// the side. Designed to be the user's daily launchpad.
struct DayTimelineView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedDate = Date()
    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())

    private let rowHeight: CGFloat = 56

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var monthDays: [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstOfMonth = interval.start
        let weekday = calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday
        let normalized = (weekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -normalized, to: firstOfMonth) ?? firstOfMonth
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var dayBlocks: [ScheduleBlock] {
        appState.scheduleBlocks
            .filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { $0.startHour < $1.startHour }
    }

    private var todayBlocks: [ScheduleBlock] {
        appState.scheduleBlocks.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var tasksDueToday: [HubTask] {
        let calendar = Calendar.current
        return appState.tasks
            .filter { !$0.isCompleted && calendar.isDateInToday($0.dueDate) }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var upcomingTasks: [HubTask] {
        let now = Date()
        return appState.tasks
            .filter { !$0.isCompleted && $0.dueDate > now }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(5)
            .map { $0 }
    }

    private var overdueTasks: [HubTask] {
        appState.tasks
            .filter { $0.isOverdue }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(3)
            .map { $0 }
    }

    private var blocksByDate: [Date: [ScheduleBlock]] {
        let calendar = Calendar.current
        var result: [Date: [ScheduleBlock]] = [:]
        for block in appState.scheduleBlocks {
            let day = calendar.startOfDay(for: block.date)
            result[day, default: []].append(block)
        }
        return result
    }

    private var taskCountsByDate: [Date: Int] {
        let calendar = Calendar.current
        var result: [Date: Int] = [:]
        for task in appState.tasks where !task.isCompleted {
            let day = calendar.startOfDay(for: task.dueDate)
            result[day, default: 0] += 1
        }
        return result
    }

    private var positionedBlocks: [PositionedBlock] {
        let sorted = dayBlocks
        var groups: [[ScheduleBlock]] = []
        for block in sorted {
            if var last = groups.last, let lastBlock = last.last,
               abs(block.startHour - lastBlock.startHour) < 0.001 {
                last.append(block)
                groups[groups.count - 1] = last
            } else {
                groups.append([block])
            }
        }
        var result: [PositionedBlock] = []
        for group in groups {
            let count = group.count
            for (index, block) in group.enumerated() {
                result.append(PositionedBlock(block: block, column: index, columnCount: count))
            }
        }
        return result
    }

    private struct PositionedBlock: Identifiable {
        let block: ScheduleBlock
        let column: Int
        let columnCount: Int
        var id: UUID { block.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    homeHeader
                    homeStatRow
                    monthCalendar
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            dayTimelineColumn
                                .frame(minWidth: 420, maxWidth: .infinity)
                            rightRail
                                .frame(width: 300)
                        }
                        VStack(alignment: .leading, spacing: 18) {
                            dayTimelineColumn
                            rightRail
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 28)
            }
        }
        .background(HubPalette.background)
    }

    // MARK: - Header

    private var homeHeader: some View {
        HStack(alignment: .top) {
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
            Spacer()
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
                    Button("Today") { selectedDate = today; displayedMonth = today }
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
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
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
                value: "\(todayBlocks.count)",
                label: "On calendar"
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
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(HubPalette.grouped)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HubPalette.separator, lineWidth: 0.5)
        )
    }

    // MARK: - Month calendar

    private var monthCalendar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        if let m = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) {
                            displayedMonth = m
                        }
                    } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Today") { displayedMonth = today; selectedDate = today }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button {
                        if let m = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) {
                            displayedMonth = m
                        }
                    } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            HStack(spacing: 4) {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(monthDays, id: \.self) { day in
                    monthDayCell(day)
                }
            }
        }
        .padding(18)
        .background(HubPalette.grouped)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HubPalette.separator, lineWidth: 0.5)
        )
    }

    private var weekdaySymbols: [String] {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let start = Calendar.current.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % 7] }
    }

    private func monthDayCell(_ day: Date) -> some View {
        let calendar = Calendar.current
        let inMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let blockCount = blocksByDate[calendar.startOfDay(for: day)]?.count ?? 0
        let taskCount = taskCountsByDate[calendar.startOfDay(for: day)] ?? 0
        let hasItems = blockCount > 0 || taskCount > 0
        return Button {
            selectedDate = day
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 13, weight: isToday || isSelected ? .bold : .regular))
                if hasItems {
                    HStack(spacing: 2) {
                        if blockCount > 0 {
                            Circle().fill(HubPalette.hubAccent).frame(width: 4, height: 4)
                        }
                        if taskCount > 0 {
                            Circle().fill(HubPalette.yellow).frame(width: 4, height: 4)
                        }
                    }
                } else {
                    Spacer().frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? HubPalette.hubAccent : (isToday ? HubPalette.hubAccent.opacity(0.10) : Color.clear))
            )
            .foregroundStyle(
                isSelected ? Color.white
                : (inMonth ? HubPalette.primaryText : HubPalette.tertiaryText)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day timeline

    private var dayTimelineColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                if !dayBlocks.isEmpty {
                    Text("\(dayBlocks.count) blocks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            weekStrip

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    hourGrid
                    scheduleBlocksLayer
                }
                .frame(height: rowHeight * 24)
            }
            .background(HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(HubPalette.separator, lineWidth: 0.5)
            )
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
            ForEach(0..<24, id: \.self) { hour in
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
            }
        }
        .padding(.horizontal, 14)
    }

    private var scheduleBlocksLayer: some View {
        GeometryReader { geometry in
            let leftInset: CGFloat = 78
            let rightInset: CGFloat = 14
            let columnGap: CGFloat = 6
            ForEach(positionedBlocks) { positioned in
                let availableWidth = max(1, geometry.size.width - leftInset - rightInset)
                let totalGaps = columnGap * CGFloat(max(0, positioned.columnCount - 1))
                let blockWidth = (availableWidth - totalGaps) / CGFloat(positioned.columnCount)
                ScheduleBlockView(block: positioned.block)
                    .frame(width: blockWidth)
                    .frame(height: max(48, positioned.block.duration * rowHeight - 8))
                    .offset(
                        x: leftInset + CGFloat(positioned.column) * (blockWidth + columnGap),
                        y: positioned.block.startHour * rowHeight + 7
                    )
            }
        }
    }

    // MARK: - Right rail

    private var rightRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !overdueTasks.isEmpty {
                railCard(title: "Overdue", count: overdueTasks.count) {
                    ForEach(overdueTasks) { task in
                        railTaskRow(task)
                        if task.id != overdueTasks.last?.id { Divider() }
                    }
                }
            }

            railCard(title: "Today", count: tasksDueToday.count) {
                if tasksDueToday.isEmpty {
                    Text("All clear for today.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ForEach(tasksDueToday.prefix(6)) { task in
                        railTaskRow(task)
                        if task.id != tasksDueToday.prefix(6).last?.id { Divider() }
                    }
                }
            }

            if !upcomingTasks.isEmpty {
                railCard(title: "Coming up", count: upcomingTasks.count) {
                    ForEach(upcomingTasks) { task in
                        railTaskRow(task)
                        if task.id != upcomingTasks.last?.id { Divider() }
                    }
                }
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

    private func railTaskRow(_ task: HubTask) -> some View {
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
                Text("\(task.course.title) · \(task.dueDate.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 5)
    }

    // MARK: - Helpers

    private func formatHour(_ hour: Int) -> String {
        let suffix = hour < 12 ? "AM" : "PM"
        let display = hour == 0 || hour == 12 ? 12 : hour % 12
        return "\(display) \(suffix)"
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

private struct ScheduleBlockView: View {
    let block: ScheduleBlock

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(block.course.accent)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                Text(block.subtitle)
                    .font(.system(size: 9))
                    .lineLimit(1)
            }
            Spacer()
            if block.linkedTaskID != nil {
                Image(systemName: "link")
                    .font(.system(size: 9))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(block.course.accent.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(block.course.accent.opacity(0.65), lineWidth: 1)
        }
    }
}

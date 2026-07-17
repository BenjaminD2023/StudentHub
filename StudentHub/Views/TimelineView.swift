import SwiftUI

struct DayTimelineView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedDate = Date()
    private let rowHeight: CGFloat = 64

    private struct PositionedBlock: Identifiable {
        let block: ScheduleBlock
        let column: Int
        let columnCount: Int

        var id: UUID { block.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            timelineHeader
            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    ZStack(alignment: .topLeading) {
                        hourGrid
                        scheduleBlocks
                        currentTimeLine
                    }
                    .frame(height: rowHeight * 13)

                    dropTarget
                }
                .padding(.bottom, 18)
            }
        }
        .background(HubPalette.background)
    }

    private var timelineHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).day()))
                        .font(.system(size: 30, weight: .bold))
                    Text(selectedDate.formatted(.dateTime.month(.wide).year()))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Today") { selectedDate = Date() }
                    .buttonStyle(.bordered)
                Button {
                    appState.navigate(to: .calendar)
                } label: {
                    Image(systemName: "calendar")
                }
                .buttonStyle(.bordered)
            }

            WeekStrip(selectedDate: $selectedDate)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(8..<21, id: \.self) { hour in
                HStack(spacing: 12) {
                    Text(formatHour(hour))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)

                    Rectangle()
                        .fill(Color.hubSeparator.opacity(0.60))
                        .frame(height: 1)
                }
                .frame(height: rowHeight, alignment: .top)
            }
        }
        .padding(.horizontal, 16)
    }

    private var scheduleBlocks: some View {
        GeometryReader { geometry in
            let leftInset: CGFloat = 82
            let rightInset: CGFloat = 18
            let columnGap: CGFloat = 6

            ForEach(positionedBlocks) { positioned in
                let availableWidth = max(1, geometry.size.width - leftInset - rightInset)
                let totalGaps = columnGap * CGFloat(max(0, positioned.columnCount - 1))
                let blockWidth = (availableWidth - totalGaps) / CGFloat(positioned.columnCount)

                ScheduleBlockView(block: positioned.block)
                    .frame(width: blockWidth)
                    .frame(height: max(54, positioned.block.duration * rowHeight - 8))
                    .offset(
                        x: leftInset + CGFloat(positioned.column) * (blockWidth + columnGap),
                        y: (positioned.block.startHour - 8) * rowHeight + 7
                    )
                    .contextMenu {
                        if let taskID = positioned.block.linkedTaskID {
                            Button("Open linked task") {
                                appState.selectedTaskID = taskID
                                appState.navigate(to: .tasks)
                            }
                        }
                        Button("Delete", role: .destructive) { appState.deleteScheduleBlock(positioned.block.id) }
                    }
            }
        }
    }

    private var positionedBlocks: [PositionedBlock] {
        let blocks = appState.scheduleBlocks
            .filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
            .sorted { lhs, rhs in
                lhs.startHour == rhs.startHour ? lhs.duration > rhs.duration : lhs.startHour < rhs.startHour
            }

        var result: [PositionedBlock] = []
        var group: [ScheduleBlock] = []
        var groupEnd = -Double.infinity

        func appendGroup(_ group: [ScheduleBlock], to result: inout [PositionedBlock]) {
            guard !group.isEmpty else { return }
            var columnEndHours: [Double] = []
            var assignments: [(ScheduleBlock, Int)] = []

            for block in group {
                let reusableColumn = columnEndHours.firstIndex(where: { $0 <= block.startHour })
                let column = reusableColumn ?? columnEndHours.count
                if let reusableColumn {
                    columnEndHours[reusableColumn] = block.startHour + block.duration
                } else {
                    columnEndHours.append(block.startHour + block.duration)
                }
                assignments.append((block, column))
            }

            let columnCount = max(1, columnEndHours.count)
            result.append(contentsOf: assignments.map {
                PositionedBlock(block: $0.0, column: $0.1, columnCount: columnCount)
            })
        }

        for block in blocks {
            if !group.isEmpty, block.startHour >= groupEnd {
                appendGroup(group, to: &result)
                group.removeAll(keepingCapacity: true)
                groupEnd = -Double.infinity
            }
            group.append(block)
            groupEnd = max(groupEnd, block.startHour + block.duration)
        }
        appendGroup(group, to: &result)
        return result
    }

    @ViewBuilder
    private var currentTimeLine: some View {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let hour = Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        if Calendar.current.isDateInToday(selectedDate), hour >= 8 && hour <= 20 {
            HStack(spacing: 6) {
                Text(Date.now.formatted(date: .omitted, time: .shortened))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.red)
                    .frame(width: 58, alignment: .trailing)
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                Rectangle()
                    .fill(.red)
                    .frame(height: 1)
            }
            .padding(.horizontal, 16)
            .offset(y: (hour - 8) * rowHeight)
        }
    }

    private var dropTarget: some View {
        Label("Drag a task here to schedule", systemImage: "calendar.badge.plus")
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 74)
            .background(Color.hubGroupedSecondary.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5]))
            }
            .padding(.horizontal, 16)
            .dropDestination(for: String.self) { values, _ in
                guard let value = values.first, let id = UUID(uuidString: value) else { return false }
                appState.schedule(id, at: 16, on: selectedDate)
                return true
            }
    }

    private func formatHour(_ hour: Int) -> String {
        let suffix = hour < 12 ? "AM" : "PM"
        let display = hour == 12 ? 12 : hour % 12
        return "\(display) \(suffix)"
    }
}

private struct WeekStrip: View {
    @Binding var selectedDate: Date

    private var week: [Date] {
        let calendar = Calendar.current
        let chosenDay = calendar.startOfDay(for: selectedDate)
        let weekday = calendar.component(.weekday, from: chosenDay)
        let daysFromMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: chosenDay) ?? chosenDay
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(week, id: \.self) { date in
                let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                Button {
                    selectedDate = date
                } label: {
                    VStack(spacing: 6) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(isSelected ? HubPalette.hubAccent : .secondary)
                        Text(date.formatted(.dateTime.day()))
                            .font(.title3.monospacedDigit().weight(isSelected ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isSelected ? HubPalette.hubAccent.opacity(0.16) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ScheduleBlockView: View {
    let block: ScheduleBlock

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.grid.2x2")
                .font(.caption)
                .foregroundStyle(block.course.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text(block.title)
                    .font(.headline)
                Text(timeRange)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(block.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: block.course == .chemistry ? "flask" : "ellipsis")
                .foregroundStyle(block.course.accent)
        }
        .padding(12)
        .background(block.course.accent.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(block.course.accent)
                .frame(width: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(block.course.accent.opacity(0.80), lineWidth: 1)
        }
    }

    private var timeRange: String {
        "\(format(block.startHour)) – \(format(block.startHour + block.duration))"
    }

    private func format(_ hour: Double) -> String {
        let whole = Int(hour)
        let minute = Int((hour - Double(whole)) * 60)
        let suffix = whole < 12 ? "AM" : "PM"
        let display = whole == 12 ? 12 : whole % 12
        return String(format: "%d:%02d %@", display, minute, suffix)
    }
}

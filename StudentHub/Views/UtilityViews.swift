import SwiftUI

struct CalendarWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedDate = Date()
    @State private var eventTitle = "Study block"
    @State private var eventCourse: Course = .general
    @State private var selectionStart = 16.0
    @State private var selectionEnd = 17.0

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    HubPageHeader(eyebrow: "Plan", title: "Calendar", subtitle: "Drag across the day to reserve time, or drop a task onto an hour.")
                    Spacer()
                    Button("Today") { selectedDate = Date() }.buttonStyle(.bordered)
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                        .labelsHidden()
                }

                CalendarSelectionGrid(
                    date: selectedDate,
                    selectionStart: $selectionStart,
                    selectionEnd: $selectionEnd
                )
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            VStack(alignment: .leading, spacing: 15) {
                Text("New time block")
                    .font(.system(size: 17, weight: .bold))
                Text(selectedDate.formatted(date: .complete, time: .omitted))
                    .font(.system(size: 12))
                    .foregroundStyle(HubPalette.secondaryText)
                TextField("Block title", text: $eventTitle)
                    .textFieldStyle(.roundedBorder)
                Picker("Course", selection: $eventCourse) {
                    ForEach(appState.spaces) { course in Text(course.title).tag(course) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("SELECTED TIME").font(.system(size: 9, weight: .bold)).foregroundStyle(HubPalette.secondaryText)
                    Text("\(format(selectionStart)) – \(format(selectionEnd))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                Button("Add to calendar") {
                    appState.addScheduleBlock(
                        title: eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Time block" : eventTitle,
                        course: eventCourse,
                        date: selectedDate,
                        startHour: selectionStart,
                        duration: max(0.25, selectionEnd - selectionStart)
                    )
                    appState.statusMessage = "Added to calendar"
                }
                .buttonStyle(HubProminentButtonStyle())

                Divider()
                HubSectionTitle(title: "Unscheduled tasks")
                Text("Drag a task into the calendar.")
                    .font(.system(size: 10))
                    .foregroundStyle(HubPalette.secondaryText)
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(appState.tasks.filter { !$0.isCompleted && $0.scheduledHour == nil }) { task in
                            HStack(spacing: 9) {
                                Circle().fill(task.course.accent).frame(width: 7, height: 7)
                                Text(task.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                                Spacer()
                                Image(systemName: "line.3.horizontal")
                            }
                            .padding(10)
                            .background(HubPalette.grouped)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .draggable(task.id.uuidString)
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: 300)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(HubPalette.sidebar)
        }
        .background(HubPalette.background)
    }

    private func format(_ hour: Double) -> String {
        let totalMinutes = Int((hour * 60).rounded())
        let h = totalMinutes / 60
        let minute = totalMinutes % 60
        let suffix = h < 12 ? "AM" : "PM"
        let display = h == 12 ? 12 : h % 12
        return String(format: "%d:%02d %@", display, minute, suffix)
    }
}

struct CalendarSelectionGrid: View {
    @EnvironmentObject private var appState: AppState
    let date: Date
    @Binding var selectionStart: Double
    @Binding var selectionEnd: Double
    private let startHour = 8.0
    private let endHour = 22.0
    private let rowHeight = 52.0
    @State private var dragAnchor: Double?

    private var dayBlocks: [ScheduleBlock] {
        appState.scheduleBlocks.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    var body: some View {
        ScrollView {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(Int(startHour)..<Int(endHour), id: \.self) { hour in
                            HStack(spacing: 12) {
                                Text(formatHour(hour))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(HubPalette.secondaryText)
                                    .frame(width: 48, alignment: .trailing)
                                Rectangle().fill(HubPalette.separator).frame(height: 1)
                            }
                            .frame(height: rowHeight, alignment: .top)
                        }
                    }

                    selectionOverlay
                        .padding(.leading, 68)
                        .padding(.trailing, 8)
                        .offset(y: (selectionStart - startHour) * rowHeight)

                    ForEach(dayBlocks) { block in
                        CalendarBlockCard(block: block)
                            .frame(height: max(32, block.duration * rowHeight - 5))
                            .padding(.leading, 72)
                            .padding(.trailing, 12)
                            .offset(y: (block.startHour - startHour) * rowHeight + 3)
                            .contextMenu {
                                if let taskID = block.linkedTaskID {
                                    Button("Open linked task") {
                                        appState.selectedTaskID = taskID
                                        appState.navigate(to: .tasks)
                                    }
                                }
                                Button("Delete", role: .destructive) { appState.deleteScheduleBlock(block.id) }
                            }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            let hour = snappedHour(for: value.location.y)
                            if dragAnchor == nil { dragAnchor = snappedHour(for: value.startLocation.y) }
                            let anchor = dragAnchor ?? hour
                            selectionStart = max(startHour, min(anchor, hour))
                            selectionEnd = min(endHour, max(anchor, hour) + 0.25)
                        }
                        .onEnded { _ in dragAnchor = nil }
                )
                .dropDestination(for: String.self) { values, location in
                    guard let raw = values.first, let taskID = UUID(uuidString: raw) else { return false }
                    appState.schedule(taskID, at: snappedHour(for: location.y), on: date)
                    return true
                }
            }
            .frame(height: (endHour - startHour) * rowHeight)
        }
        .hubPanel(cornerRadius: 16)
    }

    private var selectionOverlay: some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(HubPalette.hubAccent.opacity(0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(HubPalette.hubAccent, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            }
            .frame(height: max(13, (selectionEnd - selectionStart) * rowHeight))
            .allowsHitTesting(false)
    }

    private func snappedHour(for y: CGFloat) -> Double {
        let raw = startHour + Double(max(0, y)) / rowHeight
        return min(endHour - 0.25, (raw * 4).rounded() / 4)
    }

    private func formatHour(_ hour: Int) -> String {
        let suffix = hour < 12 ? "AM" : "PM"
        let display = hour == 12 ? 12 : hour % 12
        return "\(display) \(suffix)"
    }
}

struct CalendarBlockCard: View {
    let block: ScheduleBlock

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2).fill(block.course.accent).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title).font(.system(size: 11, weight: .bold)).lineLimit(1)
                Text(block.subtitle).font(.system(size: 9)).foregroundStyle(HubPalette.secondaryText).lineLimit(1)
            }
            Spacer()
            if block.linkedTaskID != nil { Image(systemName: "link").font(.system(size: 9)) }
        }
        .padding(.horizontal, 9)
        .background(block.course.accent.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(block.course.accent.opacity(0.65), lineWidth: 1) }
    }
}

struct RemindersWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var title = ""
    @State private var dueDate = Date().addingTimeInterval(3600)
    @State private var linkedTaskID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HubPageHeader(eyebrow: "Remember", title: "Reminders", subtitle: "Small nudges for things that should not become full tasks.")
            VStack(spacing: 12) {
                HStack {
                    TextField("What should I remind you?", text: $title)
                        .textFieldStyle(.plain)
                    DatePicker("", selection: $dueDate).labelsHidden()
                    Picker("Linked task", selection: $linkedTaskID) {
                        Text("No linked task").tag(Optional<UUID>.none)
                        ForEach(appState.tasks.filter { !$0.isCompleted }) { task in Text(task.title).tag(Optional(task.id)) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 190)
                    Button("Remind me") {
                        appState.addReminder(title: title, dueDate: dueDate, linkedTaskID: linkedTaskID)
                        title = ""
                    }
                    .buttonStyle(HubProminentButtonStyle())
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("The first reminder may ask for system notification permission.")
                    .font(.system(size: 10))
                    .foregroundStyle(HubPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .hubPanel(cornerRadius: 15)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(appState.reminders.sorted { $0.dueDate < $1.dueDate }) { reminder in
                        HStack(spacing: 12) {
                            Button { appState.toggleReminder(reminder.id) } label: {
                                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "bell.circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(reminder.isCompleted ? HubPalette.success : HubPalette.yellow)
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reminder.title).font(.system(size: 13, weight: .semibold)).strikethrough(reminder.isCompleted)
                                Text(reminder.dueDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10)).foregroundStyle(HubPalette.secondaryText)
                            }
                            Spacer()
                            if let taskID = reminder.linkedTaskID {
                                Button("Open task") {
                                    appState.selectedTaskID = taskID
                                    appState.navigate(to: .tasks)
                                }
                                .buttonStyle(.bordered)
                            }
                            Button(role: .destructive) { appState.deleteReminder(reminder.id) } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain)
                        }
                        .padding(13)
                        .hubPanel(cornerRadius: 12)
                    }
                }
            }
        }
        .padding(24)
        .background(HubPalette.background)
    }
}

struct PomodoroWorkspaceView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("FOCUS SESSION")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(HubPalette.secondaryText)
            Text(appState.pomodoroLabel)
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.48)
                .lineLimit(1)
                .padding(.horizontal, 20)
            Picker("Focus task", selection: $appState.pomodoroLinkedTaskID) {
                Text("No linked task").tag(Optional<UUID>.none)
                ForEach(appState.tasks.filter { !$0.isCompleted }) { task in Text(task.title).tag(Optional(task.id)) }
            }
            .frame(maxWidth: 360)
            HStack(spacing: 12) {
                Button(appState.pomodoroRunning ? "Pause" : "Start") { appState.togglePomodoro() }
                    .buttonStyle(HubProminentButtonStyle())
                    .controlSize(.large)
                Button("25 min") { appState.resetPomodoro(minutes: 25) }.buttonStyle(.bordered)
                Button("5 min break") { appState.resetPomodoro(minutes: 5) }.buttonStyle(.bordered)
            }
            Text("The timer keeps running while you use other Student Hub pages.")
                .font(.system(size: 11))
                .foregroundStyle(HubPalette.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Circle()
                .fill(HubPalette.hubAccent.opacity(0.08))
                .frame(width: 430, height: 430)
        )
        .background(HubPalette.background)
    }
}

struct ExportWorkspaceView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HubPageHeader(eyebrow: "Output", title: "Export workspace", subtitle: "Create portable task and project files you can submit, print, or archive.")
            HStack(spacing: 14) {
                exportCard(icon: "tablecells", title: "CSV", detail: "Assignments and tasks for spreadsheets")
                exportCard(icon: "doc.plaintext", title: "Markdown", detail: "Readable project summary with task lists")
            }
            Button {
                appState.exportWorkspace()
            } label: {
                Label("Export CSV + Markdown", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(HubProminentButtonStyle())
            .controlSize(.large)

            if !appState.lastExportURLs.isEmpty {
                Divider()
                HubSectionTitle(title: "Latest export")
                ForEach(appState.lastExportURLs, id: \.self) { url in
                    HStack {
                        Image(systemName: "doc")
                        Text(url.lastPathComponent).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("Open") { OpenURLHelper.open(url) }.buttonStyle(.bordered)
                        Button("Reveal") { OpenURLHelper.reveal(url) }.buttonStyle(.bordered)
                    }
                    .padding(12)
                    .hubPanel(cornerRadius: 12)
                }
            }
            Spacer()
            Text("Saved in Documents → Student Hub Library → Exports")
                .font(.system(size: 11))
                .foregroundStyle(HubPalette.secondaryText)
        }
        .padding(24)
        .background(HubPalette.background)
    }

    private func exportCard(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(HubPalette.hubAccent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .bold))
                Text(detail).font(.system(size: 11)).foregroundStyle(HubPalette.secondaryText)
            }
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .hubPanel(cornerRadius: 15)
    }
}

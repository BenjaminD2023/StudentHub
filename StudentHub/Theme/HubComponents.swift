import SwiftUI

// MARK: - Sync Status Pill

/// A small pill that summarizes the current iCloud sync state.
/// Reused across iPhone, iPad, and Mac shells.
struct SyncStatusPill: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            dot
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HubPalette.secondaryText)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(
            Capsule().fill(HubPalette.grouped)
        )
        .overlay(
            Capsule().stroke(HubPalette.separator, lineWidth: 0.5)
        )
        .accessibilityLabel(Text("iCloud sync \(label)"))
    }

    @ViewBuilder
    private var dot: some View {
        switch appState.cloudSyncStatus {
        case .localOnly:
            Circle()
                .fill(HubPalette.secondaryText)
                .frame(width: 6, height: 6)
        case .checking, .syncing:
            Circle()
                .fill(HubPalette.hubAccent)
                .frame(width: 6, height: 6)
                .modifier(PulseModifier())
        case .synced:
            Circle()
                .fill(HubPalette.success)
                .frame(width: 6, height: 6)
        case .unavailable:
            Circle()
                .fill(HubPalette.red)
                .frame(width: 6, height: 6)
        }
    }

    private var label: String {
        switch appState.cloudSyncStatus {
        case .localOnly: return "Local only"
        case .checking: return "Checking…"
        case .syncing: return "Syncing…"
        case .synced: return "Synced"
        case .unavailable: return "Sync off"
        }
    }
}

private struct PulseModifier: ViewModifier {
    @State private var pulsing = false
    func body(content: Content) -> some View {
        content
            .opacity(pulsing ? 0.4 : 1.0)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

// MARK: - Quick Capture Field

/// A search-bar-style field that accepts a natural-language task.
/// On submit, it routes through `CommandInterpreter` so the existing
/// "math hw tomorrow 8pm" style commands keep working everywhere.
struct QuickCaptureField: View {
    @EnvironmentObject private var appState: AppState
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var compact: Bool = false
    var onCommit: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(HubPalette.tertiaryText)
            TextField("Quick capture — try “Math hw tomorrow 8pm”", text: $text)
                .focused($isFocused)
                .textFieldStyle(.plain)
                .font(.system(size: compact ? 14 : 15))
                .submitLabel(.done)
                .onSubmit(commit)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: commit) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(HubPalette.hubAccent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add task")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 8 : 10)
        .background(HubPalette.grouped)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HubPalette.separator, lineWidth: 0.5)
        )
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let interpretation = CommandInterpreter.interpret(
            trimmed,
            now: Date(),
            calendar: .current,
            spaces: appState.spaces
        )
        switch interpretation.intent {
        case .createTask:
            appState.createTask(from: interpretation.draft)
        case .capture(let capture):
            guard !capture.isEmpty else { return }
            appState.addCapture(capture)
        case .createProject:
            let deadline = interpretation.draft.recognizedTokens.contains(where: { $0.kind == .date })
                ? interpretation.draft.dueDate
                : (Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
            _ = appState.addProject(title: interpretation.draft.title, course: interpretation.draft.course, deadline: deadline)
            appState.navigate(to: .projects)
        case .createNote:
            let note = appState.addNote(title: interpretation.draft.title, folder: interpretation.draft.course.title, course: interpretation.draft.course)
            appState.openNote(note.id)
            appState.navigate(to: .notes)
        case .rescheduleTask(let query):
            guard appState.rescheduleTask(matching: query, to: interpretation.draft.dueDate) != nil else {
                appState.statusMessage = "No task matched “\(query)”"
                return
            }
        case .search(let query):
            appState.statusMessage = "Open Tasks to search for “\(query)”"
            appState.navigate(to: .tasks)
        case .startTimer(let timer):
            appState.startFocusTimer(timer)
            appState.navigate(to: .pomodoro)
        }
        if case .startTimer = interpretation.intent { } else { appState.statusMessage = interpretation.summary }
        text = ""
        isFocused = false
        onCommit?(trimmed)
    }
}

// MARK: - Schedule Block Card (timeline)

/// A colored block used in the Today timeline and the day timeline.
/// Renders the course color, title, and subtitle.
struct ScheduleBlockCard: View {
    let block: ScheduleBlock
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(block.course.accent)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .lineLimit(1)
                if !block.subtitle.isEmpty {
                    Text(block.subtitle)
                        .font(.system(size: compact ? 11 : 12))
                        .foregroundStyle(HubPalette.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if block.linkedTaskID != nil {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundStyle(HubPalette.tertiaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, compact ? 6 : 8)
        .background(block.course.accent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(block.course.accent.opacity(0.45), lineWidth: 0.5)
        )
    }
}

// MARK: - Task Checklist Row

/// A row for a single task with leading circular checkbox.
/// Used in the iPhone/iPad tasks list.
struct TaskChecklistRow: View {
    @EnvironmentObject private var appState: AppState
    let task: HubTask
    var showSpace: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    appState.toggleComplete(task.id)
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(task.isCompleted ? HubPalette.success : task.course.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 16, weight: .medium))
                    .strikethrough(task.isCompleted, color: HubPalette.tertiaryText)
                    .foregroundStyle(task.isCompleted ? HubPalette.tertiaryText : HubPalette.primaryText)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if showSpace {
                        Circle()
                            .fill(task.course.accent)
                            .frame(width: 6, height: 6)
                        Text(task.course.title)
                            .font(.system(size: 12))
                            .foregroundStyle(HubPalette.secondaryText)
                    }
                    if showSpace {
                        Text("·").font(.system(size: 12)).foregroundStyle(HubPalette.tertiaryText)
                    }
                    Text(dueLabel)
                        .font(.system(size: 12, weight: task.isOverdue ? .semibold : .regular))
                        .foregroundStyle(task.isOverdue ? HubPalette.red : HubPalette.secondaryText)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var dueLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(task.dueDate) {
            return "Today · \(task.dueTimeLabel)"
        }
        if calendar.isDateInYesterday(task.dueDate) {
            return "Yesterday"
        }
        if calendar.isDateInTomorrow(task.dueDate) {
            return "Tomorrow · \(task.dueTimeLabel)"
        }
        return task.dueDate.formatted(date: .abbreviated, time: .shortened)
    }
}

extension HubTask {
    /// True if the due date is strictly before "now" and the task is open.
    var isOverdue: Bool {
        !isCompleted && dueDate < Date()
    }
}

// MARK: - Section Header (uppercase eyebrow)

/// Compact section header used in scrollable iPhone/iPad pages.
struct HubSectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(HubPalette.secondaryText)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HubPalette.hubAccent)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }
}

// MARK: - Greeting Banner

/// Used at the top of the iPhone/iPad Today view.
struct TodayGreetingBanner: View {
    @EnvironmentObject private var appState: AppState
    var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greeting)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(HubPalette.secondaryText)
            Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(HubPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                SyncStatusPill()
                if let detail = appState.cloudSyncDetail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(HubPalette.tertiaryText)
                        .lineLimit(1)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 4..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        case 18..<22: return "Good evening"
        default: return "Good night"
        }
    }
}

// MARK: - More Card (used in More view and iPad More)

struct MoreCard: View {
    let title: String
    let count: String?
    let iconName: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                )
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HubPalette.primaryText)
            if let count {
                Text(count)
                    .font(.system(size: 12))
                    .foregroundStyle(HubPalette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .padding(14)
        .background(HubPalette.grouped)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HubPalette.separator, lineWidth: 0.5)
        )
    }
}

// MARK: - Empty state placeholder

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(HubPalette.tertiaryText)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HubPalette.primaryText)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(HubPalette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

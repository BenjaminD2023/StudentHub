import SwiftUI

struct WorkspaceContentView: View {
    let section: HubSection

    var body: some View {
        Group {
            switch section {
            case .today:
                DayTimelineView()
            case .inbox:
                TasksWorkspaceView(mode: .inbox)
            case .calendar:
                CalendarWorkspaceView()
            case .tasks:
                TasksWorkspaceView(mode: .all)
            case .projects:
                ProjectsWorkspaceView()
            case .notes:
                NotesWorkspaceView()
            case .files:
                FilesWorkspaceView()
            case .journal:
                JournalWorkspaceView()
            case .meetings:
                MeetingsWorkspaceView()
            case .reminders:
                RemindersWorkspaceView()
            case .pomodoro:
                PomodoroWorkspaceView()
            case .export:
                ExportWorkspaceView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HubPageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(HubPalette.secondaryText)
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(HubPalette.primaryText)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(HubPalette.secondaryText)
        }
    }
}

struct HubEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(HubPalette.secondaryText)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(HubPalette.secondaryText)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

struct HubSectionTitle: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HubPalette.secondaryText)
            }
        }
    }
}

import SwiftUI

/// iPad More view. Shows the existing macOS workspace views for any
/// secondary section (Projects, Files, Journal, etc.) when picked
/// from the sidebar.
struct IPadMoreView: View {
    @EnvironmentObject private var appState: AppState
    let section: HubSection

    var body: some View {
        switch section {
        case .projects: ProjectsWorkspaceView()
        case .files: FilesWorkspaceView()
        case .journal: JournalWorkspaceView()
        case .meetings: MeetingsWorkspaceView()
        case .reminders: RemindersWorkspaceView()
        case .pomodoro: PomodoroWorkspaceView()
        case .export: ExportWorkspaceView()
        case .spaceHome: SpaceWorkspaceView()
        default: EmptyStateView(systemImage: "questionmark", title: "Not available", message: "Pick another section from the sidebar.")
        }
    }
}

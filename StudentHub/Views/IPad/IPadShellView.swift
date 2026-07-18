import SwiftUI

/// iPad shell using NavigationSplitView. The sidebar lists every
/// primary section; the detail area shows the selected view.
/// Reuses the iPhone view implementations where it makes sense, and
/// provides 2-column variants where there's more horizontal space.
struct IPadShellView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSection: HubSection = .today
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            IPadSidebar(selected: $selectedSection)
        } detail: {
            IPadDetailView(section: selectedSection)
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarTrailing) {
                        SyncStatusPill()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            appState.isQuickCommandPresented = true
                        } label: {
                            Image(systemName: "command")
                        }
                        .accessibilityLabel("Open Command Hub")
                    }
                    #endif
                }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(HubPalette.hubAccent)
        .onChange(of: selectedSection) { _, new in
            if new == .spaceHome, appState.selectedSpaceID == nil {
                appState.selectedSpaceID = appState.spaces.first?.id
            }
            // Mirror selection into appState so WorkspaceContentView can pick it up.
            appState.selectedSection = new
        }
        .onChange(of: appState.selectedSection) { _, new in
            if selectedSection != new { selectedSection = new }
        }
        .sheet(isPresented: $appState.isQuickCommandPresented) {
            QuickCommandView(onDismiss: { appState.isQuickCommandPresented = false })
                .environmentObject(appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// Routes from the selected `HubSection` to the right iPad view.
/// Most of the work is shared with iPhone; we just give the heavy
/// views (Today, Tasks, Notes) a 2-column treatment.
struct IPadDetailView: View {
    @EnvironmentObject private var appState: AppState
    let section: HubSection

    var body: some View {
        switch section {
        case .today: IPadTodayView()
        case .tasks, .inbox: IPadTasksView()
        case .calendar: IPhoneCalendarView()
        case .notes: IPadNotesView()
        case .projects, .files, .journal, .meetings, .reminders, .pomodoro, .export: IPadMoreView(section: section)
        case .spaceHome: SpaceWorkspaceView()
        }
    }
}

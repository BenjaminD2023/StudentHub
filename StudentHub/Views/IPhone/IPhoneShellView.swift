import SwiftUI

/// iPhone shell with a 5-tab bottom bar. Each tab owns its own
/// NavigationStack so deep links push into the right context.
struct IPhoneShellView: View {
    private enum Tab: Hashable {
        case today
        case tasks
        case calendar
        case notes
        case more

        var section: HubSection? {
            switch self {
            case .today: .today
            case .tasks: .tasks
            case .calendar: .calendar
            case .notes: .notes
            case .more: nil
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: Tab = .today
    @State private var secondarySection: HubSection?

    var body: some View {
        TabView(selection: $selectedTab) {
            IPhoneTodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(Tab.today)

            IPhoneTasksView()
                .tabItem { Label("Tasks", systemImage: "checkmark.circle") }
                .tag(Tab.tasks)

            IPhoneCalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(Tab.calendar)

            IPhoneNotesView()
                .tabItem { Label("Notes", systemImage: "doc.text") }
                .tag(Tab.notes)

            IPhoneMoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(Tab.more)
        }
        .tint(HubPalette.hubAccent)
        .onChange(of: selectedTab) { _, tab in
            if let section = tab.section { appState.selectedSection = section }
        }
        .onChange(of: appState.selectedSection) { _, section in
            route(to: section)
        }
        .onAppear { route(to: appState.selectedSection) }
        .sheet(item: $secondarySection, onDismiss: {
            if let section = selectedTab.section { appState.selectedSection = section }
        }) { section in
            NavigationStack {
                Group {
                    if section == .spaceHome {
                        IPhoneSpacesView()
                    } else {
                        CompactWorkspaceContentView(section: section)
                    }
                }
                .navigationTitle(section.title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { secondarySection = nil }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $appState.isQuickCommandPresented) {
            QuickCommandView(onDismiss: { appState.isQuickCommandPresented = false })
                .environmentObject(appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func route(to section: HubSection) {
        switch section {
        case .today, .inbox:
            selectedTab = section == .today ? .today : .tasks
        case .tasks: selectedTab = .tasks
        case .calendar: selectedTab = .calendar
        case .notes: selectedTab = .notes
        case .projects, .files, .journal, .meetings, .reminders, .pomodoro, .export, .spaceHome:
            secondarySection = section
        }
    }
}

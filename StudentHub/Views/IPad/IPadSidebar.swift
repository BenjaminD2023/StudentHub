import SwiftUI

/// iPad sidebar — primary navigation rail. Mirrors the Mac sidebar
/// but lives inside a `NavigationSplitView` column.
struct IPadSidebar: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selected: HubSection

    var body: some View {
        List(selection: $selected) {
            Section {
                Label("Today", systemImage: "sun.max").tag(HubSection.today)
                Label("Inbox", systemImage: "tray").tag(HubSection.inbox)
            } header: { Text("Now") }

            Section {
                Label("All Tasks", systemImage: "checkmark.circle")
                    .tag(HubSection.tasks)
                Label("Calendar", systemImage: "calendar")
                    .tag(HubSection.calendar)
                Label("Projects", systemImage: "folder")
                    .tag(HubSection.projects)
                Label("Pomodoro", systemImage: "timer")
                    .tag(HubSection.pomodoro)
            } header: { Text("Plan") }

            Section {
                Label("Notes", systemImage: "doc.text").tag(HubSection.notes)
                Label("Files & PDFs", systemImage: "doc").tag(HubSection.files)
                Label("Journal", systemImage: "book").tag(HubSection.journal)
                Label("Meetings", systemImage: "person.3").tag(HubSection.meetings)
                Label("Reminders", systemImage: "bell").tag(HubSection.reminders)
            } header: { Text("Library") }

            Section {
                ForEach(appState.spaces) { space in
                    HStack {
                        Circle().fill(space.accent).frame(width: 8, height: 8)
                        Text(space.title)
                    }
                    .tag(HubSection.tasks)
                }
            } header: { Text("Spaces") }

            Section {
                Label("Export", systemImage: "square.and.arrow.up")
                    .tag(HubSection.export)
            } header: { Text("Output") }
        }
        .listStyle(.sidebar)
        .navigationTitle("Student Hub")
        .safeAreaInset(edge: .bottom) {
            HStack {
                SyncStatusPill()
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

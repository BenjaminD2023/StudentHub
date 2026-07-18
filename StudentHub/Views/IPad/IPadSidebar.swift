import SwiftUI

/// iPad sidebar — primary navigation rail. Mirrors the Mac sidebar
/// but lives inside a `NavigationSplitView` column.
struct IPadSidebar: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selected: HubSection

    var body: some View {
        List {
            Section {
                navigationRow("Today", systemImage: "sun.max", section: .today)
                navigationRow("Inbox", systemImage: "tray", section: .inbox)
            } header: { Text("Now") }

            Section {
                navigationRow("All Tasks", systemImage: "checkmark.circle", section: .tasks)
                navigationRow("Calendar", systemImage: "calendar", section: .calendar)
                navigationRow("Projects", systemImage: "folder", section: .projects)
                navigationRow("Pomodoro", systemImage: "timer", section: .pomodoro)
            } header: { Text("Plan") }

            Section {
                navigationRow("Notes", systemImage: "doc.text", section: .notes)
                navigationRow("Files & PDFs", systemImage: "doc", section: .files)
                navigationRow("Journal", systemImage: "book", section: .journal)
                navigationRow("Meetings", systemImage: "person.3", section: .meetings)
                navigationRow("Reminders", systemImage: "bell", section: .reminders)
            } header: { Text("Library") }

            Section("Spaces") {
                ForEach(appState.spaces) { space in
                    Button {
                        appState.selectedSpaceID = space.id
                        selected = .spaceHome
                    } label: {
                        HStack {
                            Circle().fill(space.accent).frame(width: 8, height: 8)
                            Text(space.title)
                            Spacer()
                            if appState.selectedSpaceID == space.id && selected == .spaceHome {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(HubPalette.hubAccent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        appState.selectedSpaceID == space.id && selected == .spaceHome
                            ? HubPalette.hubAccent.opacity(0.12)
                            : Color.clear
                    )
                }
            }

            Section {
                navigationRow("Export", systemImage: "square.and.arrow.up", section: .export)
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

    private func navigationRow(
        _ title: String,
        systemImage: String,
        section: HubSection
    ) -> some View {
        Button {
            selected = section
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            selected == section ? HubPalette.hubAccent.opacity(0.12) : Color.clear
        )
    }
}

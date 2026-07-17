import SwiftUI

/// iPhone More tab. 2-column grid of secondary workspaces, plus a
/// sync settings section and spaces management.
struct IPhoneMoreView: View {
    @EnvironmentObject private var appState: AppState

    private var workspaceCards: [MoreCardModel] {
        [
            MoreCardModel(title: "Projects", count: "\(appState.projects.count) active", icon: "folder.fill", tint: HubPalette.hubAccent, section: .projects),
            MoreCardModel(title: "Files & PDFs", count: "\(appState.files.count) imported", icon: "doc.fill", tint: HubPalette.red, section: .files),
            MoreCardModel(title: "Journal", count: "\(appState.journalEntries.count) entries", icon: "book.fill", tint: HubPalette.hubAccent, section: .journal),
            MoreCardModel(title: "Meetings", count: "\(thisWeekMeetings()) this week", icon: "person.3.fill", tint: HubPalette.hubAccent, section: .meetings),
            MoreCardModel(title: "Reminders", count: "\(pendingReminders()) pending", icon: "bell.fill", tint: HubPalette.yellow, section: .reminders),
            MoreCardModel(title: "Pomodoro", count: pomodoroLabel, icon: "timer", tint: HubPalette.hubAccent, section: .pomodoro),
            MoreCardModel(title: "Export", count: "CSV or Markdown", icon: "square.and.arrow.up", tint: HubPalette.hubAccent, section: .export),
            MoreCardModel(title: "Spaces", count: "\(appState.spaces.count) configured", icon: "rectangle.3.group.fill", tint: HubPalette.hubAccent, section: .projects)
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(workspaceCards) { model in
                            Button { appState.navigate(to: model.section) } label: {
                                MoreCard(title: model.title, count: model.count, iconName: model.icon, tint: model.tint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Workspaces")
                        .textCase(nil)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(HubPalette.secondaryText)
                }

                Section {
                    HStack {
                        Image(systemName: appState.isCloudSyncEnabled ? "checkmark.icloud.fill" : "icloud.slash")
                            .foregroundStyle(appState.isCloudSyncEnabled ? HubPalette.success : HubPalette.tertiaryText)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("iCloud sync")
                            Text(syncDetail)
                                .font(.system(size: 12))
                                .foregroundStyle(HubPalette.secondaryText)
                        }
                        Spacer()
                        Toggle("", isOn: $appState.isCloudSyncEnabled)
                            .labelsHidden()
                    }
                } header: {
                    Text("Sync")
                        .textCase(nil)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(HubPalette.secondaryText)
                }

                Section {
                    Picker("Appearance", selection: $appState.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon).tag(mode)
                        }
                    }
                } header: {
                    Text("Appearance")
                        .textCase(nil)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(HubPalette.secondaryText)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle("More")
            .refreshable { await appState.syncNow() }
        }
    }

    private var pomodoroLabel: String {
        appState.pomodoroRunning ? "Running · \(appState.pomodoroLabel)" : "Idle · \(appState.pomodoroLabel)"
    }

    private var syncDetail: String {
        if !appState.isCloudSyncEnabled { return "Local saving only" }
        switch appState.cloudSyncStatus {
        case .synced: return "Up to date"
        case .syncing: return "Syncing…"
        case .checking: return "Checking…"
        case .unavailable(let m): return m
        case .localOnly: return "Local only"
        }
    }

    private func thisWeekMeetings() -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        return appState.meetings.filter { $0.date >= weekStart }.count
    }

    private func pendingReminders() -> Int {
        appState.reminders.filter { !$0.isCompleted }.count
    }
}

private struct MoreCardModel: Identifiable {
    let id = UUID()
    let title: String
    let count: String
    let icon: String
    let tint: Color
    let section: HubSection
}

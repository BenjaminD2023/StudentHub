import SwiftUI

/// iPhone shell with a 5-tab bottom bar. Each tab owns its own
/// NavigationStack so deep links push into the right context.
struct IPhoneShellView: View {
    var body: some View {
        TabView {
            IPhoneTodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }

            IPhoneTasksView()
                .tabItem { Label("Tasks", systemImage: "checkmark.circle") }

            IPhoneCalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }

            IPhoneNotesView()
                .tabItem { Label("Notes", systemImage: "doc.text") }

            IPhoneMoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(HubPalette.hubAccent)
    }
}

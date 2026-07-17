import SwiftUI

@main
struct StudentHubApp: App {
    @StateObject private var appState = AppState.shared
    @Environment(\.scenePhase) private var scenePhase

    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(appState)
                .preferredColorScheme(appState.appearance.colorScheme)
                #if os(macOS)
                .frame(minWidth: 980, minHeight: 700)
                #endif
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, appState.isCloudSyncEnabled else { return }
                    Task { await appState.syncNow() }
                }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 1024)
        #endif
        .commands {
            CommandMenu("Command Hub") {
                Button("Toggle Full Command Hub") {
                    appState.toggleCommandHub()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Toggle Quick Command") {
                    #if os(macOS)
                    NotificationCenter.default.post(name: .toggleQuickPanel, object: nil)
                    #else
                    appState.isQuickCommandPresented.toggle()
                    #endif
                }
                .keyboardShortcut(.space, modifiers: [.option])

                Divider()

                Button("Sync Now") {
                    if !appState.isCloudSyncEnabled { appState.isCloudSyncEnabled = true }
                    else { Task { await appState.syncNow() } }
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }
        }
    }
}

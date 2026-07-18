import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Top-level platform router. The phone gets a 5-tab TabView shell,
/// the pad gets a NavigationSplitView shell, macOS keeps the existing
/// 3-pane workspace shell.
struct AppShellView: View {
    var body: some View {
        #if os(macOS)
        MacAppShellView()
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            IPadShellView()
        } else {
            IPhoneShellView()
        }
        #endif
    }
}

#if os(macOS)
/// macOS keeps the original 3-pane layout (sidebar + content +
/// Command Hub). Small refinements only: the new sync pill in the
/// top bar, quick capture in the toolbar, and a segmented timeline
/// switcher. The existing workspace content is untouched.
private struct MacAppShellView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isCompactCommandPresented = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let showsSidebar = width >= 820
            let showsCommandHub = width >= 1120 && appState.isCommandHubVisible
            let isNarrow = width < 600
            let commandHubWidth: CGFloat = switch appState.selectedSection {
            case .today: min(680, max(580, width * 0.44))
            case .notes: min(400, max(360, width * 0.26))
            default: min(520, max(460, width * 0.34))
            }

            VStack(spacing: 0) {
                HubTopBar(
                    isNarrow: isNarrow,
                    showsNavigationMenu: !showsSidebar,
                    commandHubIsVisible: showsCommandHub,
                    onToggleCommandHub: {
                        if width >= 1120 {
                            appState.toggleCommandHub()
                        } else {
                            isCompactCommandPresented = true
                        }
                    },
                    onToggleQuickCommand: toggleQuickCommand
                )

                Divider()

                HStack(spacing: 0) {
                    if showsSidebar {
                        SidebarView()
                            .frame(width: 244)
                        Divider()
                    }

                    Group {
                        if showsSidebar {
                            WorkspaceContentView(section: appState.selectedSection)
                        } else {
                            CompactWorkspaceContentView(section: appState.selectedSection)
                        }
                    }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showsCommandHub {
                        Divider()
                        CommandHubView(onClose: appState.toggleCommandHub)
                            .frame(width: commandHubWidth)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .background(Color.hubBackground)
            .tint(.hubAccent)
            .overlay(alignment: .bottom) {
                if let status = appState.statusMessage {
                    Text(status)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .seconds(2.5))
                            if appState.statusMessage == status { appState.statusMessage = nil }
                        }
                }
            }
            .sheet(isPresented: $isCompactCommandPresented) {
                CommandHubView(onClose: { isCompactCommandPresented = false })
                    .environmentObject(appState)
                    .preferredColorScheme(appState.appearance.colorScheme)
            }
        }
    }

    private func toggleQuickCommand() {
        NotificationCenter.default.post(name: .toggleQuickPanel, object: nil)
    }
}
#else
/// iPhone/iPad unification: the iPad gets a sidebar + detail layout,
/// the iPhone gets a 5-tab shell. Both reuse the same data layer.
#endif

private struct HubTopBar: View {
    @EnvironmentObject private var appState: AppState
    let isNarrow: Bool
    let showsNavigationMenu: Bool
    let commandHubIsVisible: Bool
    let onToggleCommandHub: () -> Void
    let onToggleQuickCommand: () -> Void

    var body: some View {
        HStack(spacing: isNarrow ? 10 : 14) {
            if !isNarrow {
                Label("Student Hub", systemImage: "square.grid.2x2")
                    .font(.headline)
            }

            if showsNavigationMenu {
                Menu {
                    ForEach(HubSection.allCases) { section in
                        Button(section.title, systemImage: section.icon) {
                            appState.navigate(to: section)
                        }
                    }
                } label: {
                    if isNarrow {
                        Image(systemName: appState.selectedSection.icon)
                            .accessibilityLabel(appState.selectedSection.title)
                    } else {
                        Label(appState.selectedSection.title, systemImage: appState.selectedSection.icon)
                    }
                }
            }

            Spacer()

            Button {
                appState.togglePomodoro()
            } label: {
                if isNarrow {
                    Image(systemName: appState.pomodoroRunning ? "pause.circle" : "timer")
                        .accessibilityLabel("Pomodoro \(appState.pomodoroLabel)")
                } else {
                    Label(appState.pomodoroLabel, systemImage: appState.pomodoroRunning ? "pause.circle" : "timer")
                }
            }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .help("Start or pause Pomodoro")

            Divider()
                .frame(height: 20)

            Menu {
                Picker("Appearance", selection: $appState.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
            } label: {
                if isNarrow {
                    Image(systemName: appState.appearance.icon)
                        .accessibilityLabel(appState.appearance.title)
                } else {
                    Label(appState.appearance.title, systemImage: appState.appearance.icon)
                }
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .fixedSize()

            Button(action: onToggleCommandHub) {
                Label(
                    commandHubIsVisible ? "Hide Command Hub" : "Show Command Hub",
                    systemImage: "sidebar.right"
                )
                .labelStyle(.iconOnly)
            }
            .help("Toggle Command Hub (⇧⌘K)")
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Button(action: onToggleQuickCommand) {
                if isNarrow {
                    Image(systemName: "command.square")
                        .accessibilityLabel("Quick Command")
                } else {
                    Label("Quick Command", systemImage: "command.square")
                }
            }
            .buttonStyle(HubProminentButtonStyle())
            .controlSize(.small)
            .help("Quick Command (⌥ Space)")
        }
        .padding(.horizontal, isNarrow ? 12 : 18)
        .frame(height: 52)
        .background(Color.hubSidebar)
    }
}

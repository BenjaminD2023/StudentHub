#if os(macOS)
import AppKit
import Carbon
import SwiftUI

extension Notification.Name {
    static let toggleQuickPanel = Notification.Name("StudentHub.toggleQuickPanel")
    static let quickPanelWillOpen = Notification.Name("StudentHub.quickPanelWillOpen")
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: QuickPanelController?
    private var hotKey: GlobalHotKey?
    private var observer: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = QuickPanelController(appState: .shared)
        panelController = controller

        hotKey = GlobalHotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) {
            DispatchQueue.main.async {
                controller.toggle()
            }
        }

        observer = NotificationCenter.default.addObserver(
            forName: .toggleQuickPanel,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.async {
                controller.toggle()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        hotKey = nil
        panelController = nil
    }
}

@MainActor
final class QuickPanelController {
    private let panel: NSPanel

    init(appState: AppState) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 500),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.panel = panel

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let root = QuickCommandView(onDismiss: { [weak panel] in
            panel?.orderOut(nil)
        })
        .environmentObject(appState)

        panel.contentView = NSHostingView(rootView: root)
        panel.center()
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            NotificationCenter.default.post(name: .quickPanelWillOpen, object: nil)
            panel.center()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }
}

final class GlobalHotKey: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            owner.action()
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x53544842), id: 1)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}
#endif

import SwiftUI

/// Bottom-sheet note editor with title, folder, space, and an
/// Obsidian-style live Markdown canvas.
struct IPhoneNoteEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let noteID: UUID

    @State private var draft: HubNote?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var markdownSelection = NSRange(location: 0, length: 0)
    @State private var exportURLs: [URL] = []

    private var note: HubNote? { appState.notes.first(where: { $0.id == noteID }) }

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    Form {
                        Section("Title") {
                            TextField("Title", text: Binding(
                                get: { draft.title },
                                set: { newValue in
                                    var d = draft
                                    d.title = newValue
                                    self.draft = d
                                }
                            ))
                            .font(.system(size: 17, weight: .semibold))
                        }
                        Section("Folder") {
                            TextField("Folder", text: Binding(
                                get: { draft.folder },
                                set: { newValue in
                                    var d = draft
                                    d.folder = newValue
                                    self.draft = d
                                }
                            ))
                            Picker("Space", selection: Binding(
                                get: { draft.course },
                                set: { newValue in
                                    var d = draft
                                    d.course = newValue
                                    self.draft = d
                                }
                            )) {
                                ForEach(appState.spaces) { space in
                                    Text(space.title).tag(space)
                                }
                            }
                        }
                        Section("Markdown") {
                            ObsidianLiveMarkdownEditor(text: Binding(
                                get: { draft.markdown },
                                set: { newValue in
                                    var d = draft
                                    d.markdown = newValue
                                    self.draft = d
                                }
                            ), targetLine: nil, onSelectionChange: { markdownSelection = $0 })
                            .frame(minHeight: 360)
                        }
                        Section("Markdown tools") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(MarkdownTool.allCases) { tool in
                                        Button {
                                            insert(tool)
                                        } label: {
                                            Label(tool.title, systemImage: tool.icon)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            Text("Select text to format it, or insert at the cursor.")
                                .font(.caption)
                                .foregroundStyle(HubPalette.secondaryText)
                        }
                        Section("Export") {
                            Button {
                                appState.updateNote(draft)
                                exportURLs = appState.exportNote(draft)
                            } label: {
                                Label("Create PDF, Word-compatible RTF & CSV", systemImage: "square.and.arrow.up")
                            }
                            if !exportURLs.isEmpty {
                                ShareLink(items: exportURLs) {
                                    Label("Share exported files", systemImage: "square.and.arrow.up.on.square")
                                }
                            }
                        }
                    }
                } else {
                    EmptyStateView(
                        systemImage: "doc.text",
                        title: "Note not found",
                        message: "It may have been removed."
                    )
                }
            }
            .navigationTitle("Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let draft { appState.updateNote(draft) }
                        dismiss()
                    }
                    .disabled(draft == nil)
                }
            }
            .onAppear {
                if draft == nil { draft = note }
            }
            .onChange(of: noteID) { _, _ in
                draft = note
            }
            .onChange(of: draft) { _, newValue in
                scheduleAutosave(newValue)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            autosaveTask?.cancel()
            if let draft { appState.updateNote(draft) }
        }
    }

    private func insert(_ tool: MarkdownTool) {
        guard var draft else { return }
        let result = tool.applying(to: draft.markdown, selection: markdownSelection)
        draft.markdown = result.text
        markdownSelection = result.selection
        self.draft = draft
    }

    private func scheduleAutosave(_ note: HubNote?) {
        autosaveTask?.cancel()
        guard let note else { return }
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            appState.updateNote(note)
        }
    }
}

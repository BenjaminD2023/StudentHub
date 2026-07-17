import SwiftUI

/// Bottom-sheet note editor with title, folder, space, and a
/// monospaced Markdown body.
struct IPhoneNoteEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let noteID: UUID

    @State private var draft: HubNote?

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
                            TextEditor(text: Binding(
                                get: { draft.markdown },
                                set: { newValue in
                                    var d = draft
                                    d.markdown = newValue
                                    self.draft = d
                                }
                            ))
                            .font(.system(size: 14, design: .monospaced))
                            .frame(minHeight: 280)
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
            #if os(iOS)

            .navigationBarTitleDisplayMode(.inline)

            #endif
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
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

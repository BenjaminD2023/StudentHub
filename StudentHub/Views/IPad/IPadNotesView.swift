import SwiftUI

/// iPad Notes view. Two-column layout: folder list on the left,
/// selected folder's notes on the right.
struct IPadNotesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedFolder: String? = nil
    @State private var selectedSpaceID: String? = nil
    @State private var editingNoteID: UUID?

    private var folders: [String] {
        Array(Set(appState.notes.map { $0.folder })).sorted()
    }

    private var notes: [HubNote] {
        let base = appState.notes
        let filtered: [HubNote]
        if let selectedSpaceID {
            filtered = base.filter { $0.course.id == selectedSpaceID }
        } else if let folder = selectedFolder {
            filtered = base.filter { $0.folder == folder }
        } else {
            filtered = base
        }
        return filtered.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Folder list
            List {
                Section("All") {
                    Button {
                        selectedFolder = nil
                        selectedSpaceID = nil
                    } label: {
                        Label("All Notes", systemImage: "tray.full")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selectedFolder == nil ? HubPalette.hubAccent.opacity(0.12) : Color.clear
                    )
                }
                Section("Folders") {
                    ForEach(folders, id: \.self) { folder in
                        let count = appState.notes.filter { $0.folder == folder }.count
                        Button {
                            selectedFolder = folder
                            selectedSpaceID = nil
                        } label: {
                            HStack {
                                Label(folder, systemImage: "folder")
                                Spacer()
                                Text("\(count)").foregroundStyle(HubPalette.tertiaryText)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedFolder == folder ? HubPalette.hubAccent.opacity(0.12) : Color.clear
                        )
                    }
                }
                Section("Spaces") {
                    ForEach(appState.spaces) { space in
                        let count = appState.notes.filter { $0.course.id == space.id }.count
                        Button {
                            selectedSpaceID = space.id
                            selectedFolder = nil
                        } label: {
                            HStack {
                                Circle().fill(space.accent).frame(width: 8, height: 8)
                                Text(space.title)
                                Spacer()
                                Text("\(count)").foregroundStyle(HubPalette.tertiaryText)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedSpaceID == space.id ? HubPalette.hubAccent.opacity(0.12) : Color.clear
                        )
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 240)

            Divider()

            // Notes list for selected folder
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(selectedSpaceTitle ?? selectedFolder ?? "All Notes")
                        .font(.system(size: 22, weight: .bold))
                    Spacer()
                    Button {
                        let course = appState.spaces.first(where: { $0.id == selectedSpaceID }) ?? appState.defaultSpace
                        let note = appState.addNote(folder: selectedFolder ?? "Inbox", course: course)
                        editingNoteID = note.id
                    } label: {
                        Label("New Note", systemImage: "plus")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)

                if notes.isEmpty {
                    EmptyStateView(
                        systemImage: "doc.text",
                        title: "No notes in \(selectedSpaceTitle ?? selectedFolder ?? "this collection")",
                        message: "Tap New Note to write one."
                    )
                } else {
                    List(notes) { note in
                        Button { editingNoteID = note.id } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(note.course.accent)
                                    .frame(width: 4, height: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(note.title).font(.system(size: 15, weight: .semibold))
                                    Text(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 12))
                                        .foregroundStyle(HubPalette.secondaryText)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                appState.deleteNote(note.id)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
                }
            }
        }
        .background(HubPalette.background)
        .sheet(item: editingNoteBinding) { wrapper in
            IPhoneNoteEditorView(noteID: wrapper.id)
        }
    }

    private var editingNoteBinding: Binding<IdentifiableNote?> {
        Binding(
            get: { editingNoteID.map(IdentifiableNote.init(id:)) },
            set: { editingNoteID = $0?.id }
        )
    }

    private var selectedSpaceTitle: String? {
        appState.spaces.first(where: { $0.id == selectedSpaceID })?.title
    }
}

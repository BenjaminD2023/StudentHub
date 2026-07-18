import SwiftUI

/// iPhone Notes tab. Lists notes grouped by folder with search.
struct IPhoneNotesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText: String = ""
    @State private var editingNoteID: UUID?

    private var folders: [String] {
        Array(Set(appState.notes.map { $0.folder })).sorted()
    }

    private var recentNotes: [HubNote] {
        let base = appState.notes
        let filtered = searchText.isEmpty
            ? base
            : base.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.markdown.localizedCaseInsensitiveContains(searchText)
            }
        return filtered.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AllNotesList(notes: appState.notes.sorted { $0.modifiedAt > $1.modifiedAt })
                    } label: {
                        HStack {
                            Image(systemName: "tray.full")
                                .foregroundStyle(HubPalette.hubAccent)
                                .frame(width: 24)
                            Text("All Notes")
                            Spacer()
                            Text("\(appState.notes.count)")
                                .foregroundStyle(HubPalette.tertiaryText)
                        }
                    }
                }

                Section("Folders") {
                    ForEach(folders, id: \.self) { folder in
                        let count = appState.notes.filter { $0.folder == folder }.count
                        NavigationLink {
                            AllNotesList(notes: appState.notes.filter { $0.folder == folder }.sorted { $0.modifiedAt > $1.modifiedAt })
                                .navigationTitle(folder)
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(HubPalette.hubAccent)
                                    .frame(width: 24)
                                Text(folder)
                                Spacer()
                                Text("\(count)")
                                    .foregroundStyle(HubPalette.tertiaryText)
                            }
                        }
                    }
                }

                Section("Recent") {
                    if recentNotes.isEmpty {
                        EmptyStateView(
                            systemImage: "doc.text",
                            title: "No notes yet",
                            message: "Tap + to create your first note."
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(recentNotes) { note in
                            Button { editingNoteID = note.id } label: {
                                noteRow(note)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    appState.deleteNote(note.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .navigationTitle("Notes")
            .searchable(text: $searchText, prompt: "Search notes")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let note = appState.addNote()
                        editingNoteID = note.id
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                #endif
            }
            .sheet(item: editingNoteBinding) { wrapper in
                IPhoneNoteEditorView(noteID: wrapper.id)
            }
            .refreshable { await appState.syncNow() }
        }
    }

    @ViewBuilder
    private func noteRow(_ note: HubNote) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(note.course.accent)
                .frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HubPalette.primaryText)
                    .lineLimit(1)
                Text("\(note.folder) · \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 12))
                    .foregroundStyle(HubPalette.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var editingNoteBinding: Binding<IdentifiableNote?> {
        Binding(
            get: { editingNoteID.map(IdentifiableNote.init(id:)) },
            set: { editingNoteID = $0?.id }
        )
    }
}

struct IdentifiableNote: Identifiable {
    let id: UUID
}

/// Push destination listing every note, used from the All Notes row.
private struct AllNotesList: View {
    let notes: [HubNote]
    @State private var editingNoteID: UUID?

    var body: some View {
        List(notes) { note in
            Button { editingNoteID = note.id } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title).font(.system(size: 15, weight: .semibold))
                    Text(note.folder).font(.system(size: 12)).foregroundStyle(HubPalette.secondaryText)
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("All Notes")
        .sheet(item: Binding(
            get: { editingNoteID.map(IdentifiableNote.init(id:)) },
            set: { editingNoteID = $0?.id }
        )) { wrapper in
            IPhoneNoteEditorView(noteID: wrapper.id)
        }
    }
}

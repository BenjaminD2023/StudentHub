import SwiftUI

struct NotesWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedFolder: String?
    @State private var searchText = ""

    private var folders: [String] {
        Array(Set(appState.notes.map(\.folder))).sorted()
    }

    private var visibleNotes: [HubNote] {
        appState.notes
            .filter { selectedFolder == nil || $0.folder == selectedFolder }
            .filter {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                return query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.markdown.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var body: some View {
        HStack(spacing: 0) {
            notesSidebar
            Divider()
            noteList
            Divider()
            VStack(spacing: 0) {
                NoteTabsView()
                Divider()
                if let note = appState.selectedNote {
                    MarkdownNoteEditor(note: note).id(note.id)
                } else {
                    HubEmptyState(icon: "doc.text", title: "Open a note", message: "Choose a note or create a new Markdown file.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(HubPalette.background)
    }

    private var notesSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NOTES")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(HubPalette.secondaryText)
                    Text("Workspace").font(.title3.bold())
                }
                Spacer()
                Button { _ = appState.addNote(folder: selectedFolder ?? "Inbox") } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New Markdown note")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(HubPalette.secondaryText)
                TextField("Search notes", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(HubPalette.secondaryText)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).stroke(HubPalette.separator, lineWidth: 1) }

            if !appState.openNoteIDs.isEmpty {
                sidebarLabel("OPEN TABS")
                VStack(spacing: 3) {
                    ForEach(appState.openNoteIDs, id: \.self) { id in
                        if let note = appState.notes.first(where: { $0.id == id }) {
                            Button { appState.selectedNoteID = id } label: {
                                HStack(spacing: 9) {
                                    Circle().fill(note.course.accent).frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(note.title).lineLimit(1)
                                        Text(note.folder).font(.caption2).foregroundStyle(HubPalette.secondaryText)
                                    }
                                    Spacer()
                                    if appState.selectedNoteID == id { Image(systemName: "chevron.right").font(.caption2) }
                                }
                                .font(.system(size: 11, weight: appState.selectedNoteID == id ? .semibold : .medium))
                                .padding(.horizontal, 9)
                                .frame(height: 38)
                                .background(appState.selectedNoteID == id ? HubPalette.selected : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            sidebarLabel("FOLDERS")
            Button { selectFolder(nil) } label: {
                folderRow(icon: "tray.full", label: "All notes", count: appState.notes.count, isSelected: selectedFolder == nil)
            }
            .buttonStyle(.plain)
            ForEach(folders, id: \.self) { folder in
                Button { selectFolder(folder) } label: {
                    folderRow(
                        icon: "folder.fill",
                        label: folder,
                        count: appState.notes.filter { $0.folder == folder }.count,
                        isSelected: selectedFolder == folder
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { OpenURLHelper.reveal(WorkspaceStorage.notesURL) } label: {
                Label("Open Notes folder", systemImage: "folder")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 228)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(HubPalette.sidebar)
    }

    private var noteList: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedFolder ?? "All notes").font(.system(size: 14, weight: .bold))
                    Text(searchText.isEmpty ? "Click a note to open it in a tab" : "Results for “\(searchText)”")
                        .font(.caption2)
                        .foregroundStyle(HubPalette.secondaryText)
                }
                Spacer()
                Text("\(visibleNotes.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HubPalette.secondaryText)
            }
            .padding(14)
            Divider()
            if visibleNotes.isEmpty {
                HubEmptyState(icon: "doc.text.magnifyingglass", title: "No matching notes", message: "Try another search or choose All notes.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(visibleNotes) { note in noteRow(note) }
                    }
                    .padding(10)
                }
            }
        }
        .frame(width: 258)
        .background(HubPalette.background)
    }

    private func sidebarLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(HubPalette.secondaryText)
            .padding(.horizontal, 8)
            .padding(.top, 2)
    }

    private func selectFolder(_ folder: String?) {
        selectedFolder = folder
        let candidates = appState.notes
            .filter { folder == nil || $0.folder == folder }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        if let first = candidates.first { appState.openNote(first.id) }
    }

    private func folderRow(icon: String, label: String, count: Int, isSelected: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(isSelected ? HubPalette.hubAccent : HubPalette.secondaryText)
            Text(label).lineLimit(1)
            Spacer()
            Text("\(count)").foregroundStyle(HubPalette.secondaryText)
        }
        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(isSelected ? HubPalette.selected : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func noteRow(_ note: HubNote) -> some View {
        Button { appState.openNote(note.id) } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(note.course.accent).frame(width: 5, height: 39)
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        Text(note.folder)
                        Text("·")
                        Text(note.modifiedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(HubPalette.secondaryText)
                }
                Spacer()
                Image(systemName: appState.openNoteIDs.contains(note.id) ? "rectangle.stack.fill" : "plus.square.on.square")
                    .font(.caption)
                    .foregroundStyle(appState.openNoteIDs.contains(note.id) ? note.course.accent : HubPalette.secondaryText)
            }
            .padding(10)
            .background(appState.selectedNoteID == note.id ? HubPalette.selected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(note.title) in a tab")
    }
}

struct NoteTabsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(appState.openNoteIDs, id: \.self) { id in
                    if let note = appState.notes.first(where: { $0.id == id }) {
                        HStack(spacing: 8) {
                            Circle().fill(note.course.accent).frame(width: 6, height: 6)
                            Button { appState.selectedNoteID = id } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(note.title).lineLimit(1)
                                    Text(note.folder)
                                        .font(.system(size: 8))
                                        .foregroundStyle(HubPalette.secondaryText)
                                }
                            }
                            .buttonStyle(.plain)
                            Button { appState.closeNote(id) } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.system(size: 11, weight: appState.selectedNoteID == id ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(appState.selectedNoteID == id ? HubPalette.grouped : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .bottom) {
                            if appState.selectedNoteID == id {
                                Capsule().fill(note.course.accent).frame(height: 2).padding(.horizontal, 8)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 46)
        .background(HubPalette.sidebar)
    }
}

struct MarkdownNoteEditor: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft: HubNote
    @State private var showsPreview = false
    @State private var targetHeadingLine: Int?

    init(note: HubNote) {
        _draft = State(initialValue: note)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    TextField("Title", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .bold))
                    Button("Save") { save() }
                        .buttonStyle(HubProminentButtonStyle())
                        .keyboardShortcut("s", modifiers: .command)
                }

                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder").foregroundStyle(HubPalette.secondaryText)
                        TextField("Folder", text: $draft.folder).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .frame(minWidth: 72, maxWidth: 125, minHeight: 28)
                    .background(HubPalette.grouped)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(HubPalette.separator, lineWidth: 1) }
                    Picker("Course", selection: $draft.course) {
                        ForEach(appState.spaces) { course in Text(course.title).tag(course) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 112)
                    Spacer(minLength: 0)
                    Button { showsPreview.toggle() } label: {
                        Image(systemName: showsPreview ? "pencil" : "doc.richtext")
                    }
                    .buttonStyle(.bordered)
                    .help(showsPreview ? "Edit Markdown" : "Preview Markdown")
                    Menu {
                        ForEach(appState.tasks.filter { !$0.isCompleted }) { task in
                            Button {
                                save()
                                appState.toggleLink(noteID: draft.id, taskID: task.id)
                                if let refreshed = appState.notes.first(where: { $0.id == draft.id }) { draft = refreshed }
                            } label: {
                                Label(task.title, systemImage: draft.linkedTaskIDs.contains(task.id) ? "checkmark" : "link")
                            }
                        }
                    } label: {
                        Image(systemName: "link")
                    }
                    #if os(macOS)
                    .menuStyle(.borderlessButton)
                    #endif
                    .help("Link this note to a task")
                    Menu {
                        if headings.isEmpty {
                            Text("Add a Markdown heading to create quick jumps")
                        } else {
                            ForEach(headings) { heading in
                                Button(heading.title) { jump(to: heading.line) }
                            }
                        }
                    } label: {
                        Image(systemName: "list.bullet.indent")
                    }
                    #if os(macOS)
                    .menuStyle(.borderlessButton)
                    #endif
                    .help("Jump to a heading")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            Divider()

            HStack(spacing: 0) {
                if showsPreview {
                    MarkdownReadingView(source: draft.markdown, targetLine: targetHeadingLine)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TextEditor(text: $draft.markdown)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(HubPalette.background)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if !appState.isCommandHubVisible {
                    Divider()
                    noteOutline.frame(width: 154)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Text("Markdown • \(draft.markdown.split(whereSeparator: \.isWhitespace).count) words")
                Spacer()
                if !draft.linkedTaskIDs.isEmpty {
                    Text("\(draft.linkedTaskIDs.count) linked task\(draft.linkedTaskIDs.count == 1 ? "" : "s")")
                }
                Button("Reveal in Finder") {
                    save(showStatus: false)
                    if let url = appState.noteURL(draft.id) { OpenURLHelper.reveal(url) }
                }
                .buttonStyle(.plain)
                Button(role: .destructive) {
                    appState.deleteNote(draft.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(HubPalette.secondaryText)
            .padding(.horizontal, 14)
            .frame(height: 30)
        }
        .onDisappear { save(showStatus: false) }
    }

    private var noteOutline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("OUTLINE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(HubPalette.secondaryText)
                Spacer()
                Text("\(headings.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(HubPalette.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            if headings.isEmpty {
                Text("Add headings like ## Sources to create quick jumps.")
                    .font(.caption)
                    .foregroundStyle(HubPalette.secondaryText)
                    .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(headings) { heading in
                            Button {
                                jump(to: heading.line)
                            } label: {
                                HStack(spacing: 7) {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(draft.course.accent.opacity(heading.level == 1 ? 1 : 0.55))
                                        .frame(width: 2, height: 18)
                                    Text(heading.title).lineLimit(2).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .font(.system(size: heading.level == 1 ? 11 : 10, weight: heading.level == 1 ? .semibold : .medium))
                                .padding(.leading, CGFloat(max(heading.level - 1, 0)) * 8)
                                .padding(.horizontal, 9)
                                .frame(minHeight: 32)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Open preview at \(heading.title)")
                        }
                    }
                }
            }
            Spacer()
        }
        .background(HubPalette.sidebar)
    }

    private var headings: [MarkdownHeading] { MarkdownHeading.parse(draft.markdown) }

    private func jump(to line: Int) {
        showsPreview = true
        targetHeadingLine = nil
        DispatchQueue.main.async { targetHeadingLine = line }
    }

    private func save(showStatus: Bool = true) {
        appState.updateNote(draft)
        if showStatus { appState.statusMessage = "Saved \(draft.title).md" }
    }
}

private struct MarkdownHeading: Identifiable {
    let line: Int
    let level: Int
    let title: String
    var id: Int { line }

    static func parse(_ source: String) -> [MarkdownHeading] {
        source.components(separatedBy: .newlines).enumerated().compactMap { index, line in
            let hashes = line.prefix(while: { $0 == "#" }).count
            guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
            let title = line.dropFirst(hashes).trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : MarkdownHeading(line: index, level: hashes, title: title)
        }
    }
}

private struct MarkdownReadingView: View {
    let source: String
    let targetLine: Int?

    private var lines: [(offset: Int, element: String)] {
        Array(source.components(separatedBy: .newlines).enumerated())
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(lines, id: \.offset) { line in
                        markdownLine(line.element).id(line.offset)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .onAppear { scroll(to: targetLine, with: reader) }
            .onChange(of: targetLine) { _, line in scroll(to: line, with: reader) }
        }
    }

    @ViewBuilder
    private func markdownLine(_ source: String) -> some View {
        let hashes = source.prefix(while: { $0 == "#" }).count
        if (1...6).contains(hashes), source.dropFirst(hashes).first == " " {
            Text(source.dropFirst(hashes).trimmingCharacters(in: .whitespacesAndNewlines))
                .font(hashes == 1 ? .title2.bold() : (hashes == 2 ? .headline : .subheadline.bold()))
                .padding(.top, hashes == 1 ? 8 : 4)
        } else if source.isEmpty {
            Color.clear.frame(height: 4)
        } else {
            Text((try? AttributedString(markdown: source)) ?? AttributedString(source))
                .font(.system(size: 14))
        }
    }

    private func scroll(to line: Int?, with reader: ScrollViewProxy) {
        guard let line else { return }
        withAnimation(.easeInOut(duration: 0.2)) { reader.scrollTo(line, anchor: .top) }
    }
}

struct JournalWorkspaceView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Journal").font(.system(size: 19, weight: .bold))
                    Spacer()
                    Button {
                        appState.addJournalEntry()
                    } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                }
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(appState.journalEntries.sorted { $0.date > $1.date }) { entry in
                            Button {
                                appState.selectedJournalID = entry.id
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    HStack {
                                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                        Spacer()
                                        Text(String(repeating: "●", count: entry.mood))
                                            .foregroundStyle(HubPalette.yellow)
                                    }
                                    .font(.system(size: 9))
                                    .foregroundStyle(HubPalette.secondaryText)
                                }
                                .padding(11)
                                .background(appState.selectedJournalID == entry.id ? HubPalette.selected : HubPalette.grouped)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
            .frame(width: 260)
            .background(HubPalette.sidebar)
            Divider()
            if let entry = appState.selectedJournal {
                JournalEditor(entry: entry)
                    .id(entry.id)
            } else {
                HubEmptyState(icon: "book.closed", title: "Start a journal entry", message: "Write a private reflection for today.")
            }
        }
        .background(HubPalette.background)
    }
}

struct JournalEditor: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft: JournalEntry

    init(entry: JournalEntry) {
        _draft = State(initialValue: entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HubPageHeader(eyebrow: "Journal", title: draft.date.formatted(date: .long, time: .omitted), subtitle: "A quiet place for reflections and learning notes.")
                Spacer()
                Picker("Mood", selection: $draft.mood) {
                    ForEach(1...5, id: \.self) { mood in Text("Mood \(mood)").tag(mood) }
                }
                .frame(width: 110)
                Button("Save") {
                    appState.updateJournal(draft)
                    appState.statusMessage = "Journal saved"
                }
                .buttonStyle(HubProminentButtonStyle())
                Button(role: .destructive) {
                    appState.deleteJournal(draft.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            TextField("Entry title", text: $draft.title)
                .font(.system(size: 20, weight: .bold))
                .textFieldStyle(.plain)
            TextEditor(text: $draft.body)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(14)
                .background(HubPalette.grouped)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(HubPalette.separator, lineWidth: 1) }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

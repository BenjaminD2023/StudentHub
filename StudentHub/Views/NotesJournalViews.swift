import SwiftUI

struct NotesWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var selectedFolder: String?
    @State private var searchText = ""
    @State private var isNavigatorVisible = true
    @State private var isFocusMode = false
    @State private var commandHubWasVisible = true

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
            if isNavigatorVisible {
                notesNavigator
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }
            VStack(spacing: 0) {
                NoteTabsView(
                    isNavigatorVisible: isNavigatorVisible,
                    isFocusMode: isFocusMode,
                    onToggleNavigator: {
                        withAnimation(.easeOut(duration: 0.16)) {
                            isNavigatorVisible.toggle()
                        }
                    },
                    onToggleFocus: toggleFocusMode
                )
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
        .onDisappear {
            guard isFocusMode else { return }
            appState.isCommandHubVisible = commandHubWasVisible
        }
    }

    private var notesNavigator: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NOTES")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(HubPalette.secondaryText)
                    Text("Library").font(.title3.bold())
                }
                Spacer()
                Button { _ = appState.addNote(folder: selectedFolder ?? "Inbox") } label: {
                    Image(systemName: "square.and.pencil")
                        .frame(width: 28, height: 28)
                        .background(HubPalette.grouped)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("New Markdown note")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

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
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            HStack(spacing: 8) {
                Menu {
                    Button("All notes", systemImage: selectedFolder == nil ? "checkmark" : "tray.full") {
                        selectFolder(nil)
                    }
                    Divider()
                    ForEach(folders, id: \.self) { folder in
                        Button(folder, systemImage: selectedFolder == folder ? "checkmark" : "folder") {
                            selectFolder(folder)
                        }
                    }
                } label: {
                    Label(selectedFolder ?? "All notes", systemImage: selectedFolder == nil ? "tray.full" : "folder")
                        .font(.system(size: 12, weight: .semibold))
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif
                Spacer()
                Text("\(visibleNotes.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(HubPalette.secondaryText)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(HubPalette.sidebar)

            Divider()

            if visibleNotes.isEmpty {
                HubEmptyState(
                    icon: "doc.text.magnifyingglass",
                    title: "No matching notes",
                    message: "Try another search or choose All notes."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(visibleNotes) { note in noteRow(note) }
                    }
                    .padding(10)
                }
            }

            Button { OpenURLHelper.reveal(WorkspaceStorage.notesURL) } label: {
                Label("Open Notes folder", systemImage: "folder")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(14)
        }
        .frame(width: 262)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(HubPalette.sidebar)
    }

    private func selectFolder(_ folder: String?) {
        selectedFolder = folder
        let candidates = appState.notes
            .filter { folder == nil || $0.folder == folder }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        if let first = candidates.first { appState.openNote(first.id) }
    }

    private func toggleFocusMode() {
        withAnimation(.easeOut(duration: 0.18)) {
            if isFocusMode {
                isNavigatorVisible = true
                appState.isCommandHubVisible = commandHubWasVisible
            } else {
                commandHubWasVisible = appState.isCommandHubVisible
                isNavigatorVisible = false
                appState.isCommandHubVisible = false
            }
            isFocusMode.toggle()
        }
    }

    private func noteRow(_ note: HubNote) -> some View {
        Button { appState.openNote(note.id) } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(note.course.accent).frame(width: 3, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        Text(note.folder)
                        Text("·")
                        Text(note.modifiedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(HubPalette.secondaryText)
                }
                Spacer()
                if appState.openNoteIDs.contains(note.id) {
                    Circle().fill(note.course.accent).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 52)
            .background(appState.selectedNoteID == note.id ? HubPalette.selected : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(note.title) in a tab")
        #if os(macOS)
        .contextMenu {
            Button("Open in New Window", systemImage: "macwindow.badge.plus") {
                openWindow(value: note.id)
            }
        }
        #endif
    }
}

struct NoteTabsView: View {
    @EnvironmentObject private var appState: AppState
    let isNavigatorVisible: Bool
    let isFocusMode: Bool
    let onToggleNavigator: () -> Void
    let onToggleFocus: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleNavigator) {
                Image(systemName: "sidebar.leading")
                    .symbolVariant(isNavigatorVisible ? .fill : .none)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isNavigatorVisible ? HubPalette.hubAccent : HubPalette.secondaryText)
            .help(isNavigatorVisible ? "Hide note library" : "Show note library")

            Divider().frame(height: 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(appState.openNoteIDs, id: \.self) { id in
                        if let note = appState.notes.first(where: { $0.id == id }) {
                            HStack(spacing: 7) {
                                Circle().fill(note.course.accent).frame(width: 6, height: 6)
                                Button { appState.selectedNoteID = id } label: {
                                    Text(note.title).lineLimit(1)
                                }
                                .buttonStyle(.plain)
                                Button { appState.closeNote(id) } label: {
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.system(size: 11, weight: appState.selectedNoteID == id ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(appState.selectedNoteID == id ? HubPalette.grouped : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.vertical, 5)
            }

            Button(action: onToggleFocus) {
                Image(systemName: isFocusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isFocusMode ? HubPalette.hubAccent : HubPalette.secondaryText)
            .help(isFocusMode ? "Exit focus mode" : "Focus on this note")
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(HubPalette.sidebar)
    }
}

struct MarkdownNoteEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var draft: HubNote
    @State private var isReadingMode = false
    @State private var showsMarkdownTools = false
    @State private var targetHeadingLine: Int?
    @State private var autosaveTask: Task<Void, Never>?
    private let allowsPopOut: Bool

    init(note: HubNote, allowsPopOut: Bool = true) {
        _draft = State(initialValue: note)
        self.allowsPopOut = allowsPopOut
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    TextField("Title", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .bold))

                    Text("Autosaved")
                        .font(.caption2)
                        .foregroundStyle(HubPalette.tertiaryText)

                    Spacer(minLength: 8)

                    Button {
                        withAnimation(.easeOut(duration: 0.14)) {
                            isReadingMode.toggle()
                        }
                    } label: {
                        Image(systemName: isReadingMode ? "pencil" : "book")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isReadingMode ? HubPalette.hubAccent : HubPalette.secondaryText)
                    .help(isReadingMode ? "Return to live editing" : "Open reading view")

                    Button {
                        showsMarkdownTools.toggle()
                    } label: {
                        Image(systemName: "textformat")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .help("Markdown tools and examples")
                    .popover(isPresented: $showsMarkdownTools, arrowEdge: .bottom) {
                        MarkdownToolsPanel { tool in insert(tool) }
                    }

                    #if os(macOS)
                    if allowsPopOut {
                        Button {
                            save(showStatus: false)
                            openWindow(value: draft.id)
                        } label: {
                            Image(systemName: "macwindow.badge.plus")
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .help("Open this note in a separate window")
                    }
                    #endif

                    taskLinksMenu
                    outlineMenu
                    moreMenu
                }

                HStack(spacing: 9) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder").foregroundStyle(HubPalette.secondaryText)
                        TextField("Folder", text: $draft.folder)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 9)
                    .frame(minWidth: 92, maxWidth: 160, minHeight: 28)
                    .background(HubPalette.grouped)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Picker("Space", selection: $draft.course) {
                        ForEach(appState.spaces) { course in Text(course.title).tag(course) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 130)

                    Spacer(minLength: 0)

                    if !isReadingMode {
                        Label("Live preview", systemImage: "sparkles")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(HubPalette.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(HubPalette.sidebar)

            Divider()

            Group {
                if isReadingMode {
                    MarkdownReadingView(source: draft.markdown, targetLine: targetHeadingLine)
                        .accessibilityLabel("Markdown reading view")
                } else {
                    ObsidianLiveMarkdownEditor(text: $draft.markdown, targetLine: targetHeadingLine)
                        .accessibilityLabel("Markdown live preview editor")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(HubPalette.background)

            Divider()
            HStack {
                Label(isReadingMode ? "Reading" : "Live preview", systemImage: isReadingMode ? "book" : "sparkles")
                Text("·")
                Text("\(draft.markdown.split(whereSeparator: \.isWhitespace).count) words")
                Spacer()
                if !draft.linkedTaskIDs.isEmpty {
                    Text("\(draft.linkedTaskIDs.count) linked task\(draft.linkedTaskIDs.count == 1 ? "" : "s")")
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(HubPalette.secondaryText)
            .padding(.horizontal, 14)
            .frame(height: 30)
        }
        .onChange(of: draft) { _, _ in scheduleAutosave() }
        .onDisappear {
            autosaveTask?.cancel()
            save(showStatus: false)
        }
    }

    private var headings: [MarkdownHeading] { MarkdownHeading.parse(draft.markdown) }

    private var taskLinksMenu: some View {
        Menu {
            if appState.tasks.filter({ !$0.isCompleted }).isEmpty {
                Text("No open tasks")
            } else {
                ForEach(appState.tasks.filter { !$0.isCompleted }) { task in
                    Button {
                        save(showStatus: false)
                        appState.toggleLink(noteID: draft.id, taskID: task.id)
                        if let refreshed = appState.notes.first(where: { $0.id == draft.id }) {
                            draft = refreshed
                        }
                    } label: {
                        Label(task.title, systemImage: draft.linkedTaskIDs.contains(task.id) ? "checkmark" : "link")
                    }
                }
            }
        } label: {
            Image(systemName: "link")
                .frame(width: 28, height: 28)
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .help("Link this note to a task")
    }

    private var outlineMenu: some View {
        Menu {
            if headings.isEmpty {
                Text("Add a heading to create quick jumps")
            } else {
                ForEach(headings) { heading in
                    Button(heading.title) { jump(to: heading.line) }
                }
            }
        } label: {
            Image(systemName: "list.bullet.indent")
                .frame(width: 28, height: 28)
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .help("Jump to a heading")
    }

    private var moreMenu: some View {
        Menu {
            Button("Save now", systemImage: "checkmark") { save() }
                .keyboardShortcut("s", modifiers: .command)
            Button("Reveal in Finder", systemImage: "folder") {
                save(showStatus: false)
                if let url = appState.noteURL(draft.id) { OpenURLHelper.reveal(url) }
            }
            Divider()
            Button("Delete note", systemImage: "trash", role: .destructive) {
                appState.deleteNote(draft.id)
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 28, height: 28)
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
        .help("More note actions")
    }

    private func jump(to line: Int) {
        isReadingMode = false
        targetHeadingLine = nil
        DispatchQueue.main.async { targetHeadingLine = line }
    }

    private func insert(_ tool: MarkdownTool) {
        let needsLeadingNewline = !draft.markdown.isEmpty && !draft.markdown.hasSuffix("\n")
        draft.markdown += (needsLeadingNewline ? "\n" : "") + tool.snippet
        isReadingMode = false
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let note = draft
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            appState.updateNote(note)
        }
    }

    private func save(showStatus: Bool = true) {
        appState.updateNote(draft)
        if showStatus { appState.statusMessage = "Saved \(draft.title).md" }
    }
}

struct NoteWindowView: View {
    @EnvironmentObject private var appState: AppState
    let noteID: UUID

    var body: some View {
        Group {
            if let note = appState.notes.first(where: { $0.id == noteID }) {
                MarkdownNoteEditor(note: note, allowsPopOut: false)
                    .id(note.id)
                    .navigationTitle(note.title)
            } else {
                HubEmptyState(icon: "doc.text.magnifyingglass", title: "Note unavailable", message: "This note may have been deleted in another window.")
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .background(HubPalette.background)
    }
}

enum MarkdownTool: String, CaseIterable, Identifiable {
    case heading
    case bold
    case italic
    case checklist
    case link
    case quote
    case code
    case divider

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heading: "Heading"
        case .bold: "Bold"
        case .italic: "Italic"
        case .checklist: "Checklist"
        case .link: "Link"
        case .quote: "Quote"
        case .code: "Code"
        case .divider: "Divider"
        }
    }

    var icon: String {
        switch self {
        case .heading: "textformat.size"
        case .bold: "bold"
        case .italic: "italic"
        case .checklist: "checklist"
        case .link: "link"
        case .quote: "text.quote"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .divider: "minus"
        }
    }

    var syntax: String {
        switch self {
        case .heading: "## Heading"
        case .bold: "**bold text**"
        case .italic: "*italic text*"
        case .checklist: "- [ ] task"
        case .link: "[label](https://example.com)"
        case .quote: "> quote"
        case .code: "`code`"
        case .divider: "---"
        }
    }

    var snippet: String { syntax + "\n" }
}

private struct MarkdownToolsPanel: View {
    let onInsert: (MarkdownTool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Markdown tools").font(.headline)
                Text("Choose a format to insert an editable example.")
                    .font(.caption)
                    .foregroundStyle(HubPalette.secondaryText)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(MarkdownTool.allCases) { tool in
                    Button { onInsert(tool) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(tool.title, systemImage: tool.icon)
                                .font(.callout.weight(.semibold))
                            Text(tool.syntax)
                                .font(.caption.monospaced())
                                .foregroundStyle(HubPalette.secondaryText)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                        .padding(9)
                        .background(HubPalette.grouped)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(width: 390)
        .background(HubPalette.background)
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

struct MarkdownReadingView: View {
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

    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedEntryID: UUID?

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1 // Sunday
        return c
    }()

    private var monthDays: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstOfMonth = interval.start
        let weekday = calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday
        let normalizedWeekday = (weekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -normalizedWeekday, to: firstOfMonth) ?? firstOfMonth
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var entriesByDate: [Date: JournalEntry] {
        let cal = Calendar.current
        var result: [Date: JournalEntry] = [:]
        for entry in appState.journalEntries where entry.isDateLinked {
            let day = cal.startOfDay(for: entry.date)
            result[day] = entry
        }
        return result
    }

    private var monthEntries: [JournalEntry] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        return appState.journalEntries
            .filter { $0.isDateLinked && $0.date >= interval.start && $0.date < interval.end }
            .sorted { $0.date > $1.date }
    }

    private var undatedEntries: [JournalEntry] {
        appState.journalEntries
            .filter { !$0.isDateLinked }
            .sorted { $0.date > $1.date }
    }

    private var selectedEntry: JournalEntry? {
        if let selectedEntryID,
           let entry = appState.journalEntries.first(where: { $0.id == selectedEntryID }) {
            return entry
        }
        let day = calendar.startOfDay(for: selectedDate)
        return entriesByDate[day]
    }

    private var today: Date { calendar.startOfDay(for: Date()) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                calendarHeader
                weekdayRow
                calendarGrid
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        monthList
                        undatedList
                    }
                }
            }
            .padding(20)
            .frame(width: 360)
            .background(HubPalette.sidebar)

            Divider()

            if let entry = selectedEntry {
                JournalEditor(entry: entry)
                    .id(entry.id)
            } else {
                emptyEditor
            }
        }
        .background(HubPalette.background)
        .onAppear {
            selectedEntryID = appState.selectedJournalID
        }
    }

    // MARK: - Calendar header

    private var calendarHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Journal")
                    .font(.system(size: 22, weight: .bold))
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Button {
                    createMemo()
                } label: { Image(systemName: "note.text.badge.plus") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("New undated memo")
                Button {
                    shiftMonth(by: -1)
                } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Today") {
                    displayedMonth = today
                    selectedDate = today
                    selectedEntryID = entriesByDate[today]?.id
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button {
                    shiftMonth(by: 1)
                } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func shiftMonth(by value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    // MARK: - Weekday row

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % 7] }
    }

    // MARK: - Calendar grid

    private var calendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let entries = entriesByDate
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(monthDays, id: \.self) { day in
                let inMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
                let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
                let isToday = calendar.isDate(day, inSameDayAs: today)
                let entry = entries[calendar.startOfDay(for: day)]
                Button {
                    selectedDate = day
                    selectedEntryID = entry?.id
                } label: {
                    VStack(spacing: 3) {
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 14, weight: isToday || isSelected ? .bold : .regular))
                        Circle()
                            .fill(moodColor(entry?.mood ?? 0))
                            .frame(width: 5, height: 5)
                            .opacity(entry == nil ? 0 : 1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? HubPalette.hubAccent : (isToday ? HubPalette.hubAccent.opacity(0.10) : Color.clear))
                    )
                    .foregroundStyle(isSelected ? .white : (inMonth ? HubPalette.primaryText : HubPalette.tertiaryText))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func moodColor(_ mood: Int) -> Color {
        switch mood {
        case 0: return .clear
        case 1: return HubPalette.red
        case 2: return HubPalette.yellow.opacity(0.7)
        case 3: return HubPalette.yellow
        case 4: return Color(red: 0.4, green: 0.78, blue: 0.45)
        default: return HubPalette.success
        }
    }

    // MARK: - Month list

    private var monthList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionTitle(title: "This month", trailing: "\(monthEntries.count)")
            if monthEntries.isEmpty {
                Text("No entries this month — tap a day to add one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(monthEntries) { entry in
                        Button {
                            selectedDate = calendar.startOfDay(for: entry.date)
                            selectedEntryID = entry.id
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(moodColor(entry.mood))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.title.isEmpty ? "Untitled" : entry.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        if entry.id != monthEntries.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var undatedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionTitle(title: "Memos", trailing: "\(undatedEntries.count)")
            if undatedEntries.isEmpty {
                Button {
                    createMemo()
                } label: {
                    Label("Add an undated memo", systemImage: "note.text.badge.plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(HubPalette.hubAccent)
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(undatedEntries) { entry in
                        Button {
                            selectedEntryID = entry.id
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "note.text")
                                    .foregroundStyle(HubPalette.hubAccent)
                                Text(entry.title.isEmpty ? "Untitled memo" : entry.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        if entry.id != undatedEntries.last?.id { Divider() }
                    }
                }
            }
        }
    }

    // MARK: - Editor empty state

    private var emptyEditor: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.title2.weight(.semibold))
            Text("No journal entry for this day yet.")
                .foregroundStyle(.secondary)
            Button {
                createEntry(for: selectedDate)
            } label: {
                Label("Write entry", systemImage: "square.and.pencil")
            }
            .buttonStyle(HubProminentButtonStyle())
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HubPalette.background)
    }

    private func createEntry(for day: Date) {
        let entry = JournalEntry(
            id: UUID(),
            date: day,
            title: day.formatted(date: .long, time: .omitted),
            body: "",
            mood: 3
        )
        appState.journalEntries.insert(entry, at: 0)
        appState.selectedJournalID = entry.id
        selectedEntryID = entry.id
        appState.persist()
    }

    private func createMemo() {
        let entry = appState.addJournalMemo()
        selectedEntryID = entry.id
    }
}

struct JournalEditor: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft: JournalEntry

    init(entry: JournalEntry) {
        _draft = State(initialValue: entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HubSectionTitle(
                        title: draft.isDateLinked
                            ? draft.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
                            : "Undated memo"
                    )
                }
                Spacer()
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { mood in
                        Button {
                            draft.mood = mood
                        } label: {
                            Image(systemName: draft.mood >= mood ? "face.smiling.fill" : "face.smiling")
                                .font(.title3)
                                .foregroundStyle(draft.mood >= mood ? HubPalette.yellow : HubPalette.tertiaryText)
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(draft.mood == mood ? HubPalette.selected : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 8)
                Button("Save") {
                    appState.updateJournal(draft)
                    appState.statusMessage = "Journal saved"
                }
                .buttonStyle(HubProminentButtonStyle())
                Button(role: .destructive) {
                    appState.deleteJournal(draft.id)
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain)
                    .foregroundStyle(HubPalette.red)
            }

            TextField("Entry title", text: $draft.title)
                .font(.system(size: 24, weight: .bold))
                .textFieldStyle(.plain)
                .padding(.bottom, 4)

            HStack(spacing: 16) {
                Toggle("Linked to date", isOn: $draft.isDateLinked)
                    .toggleStyle(.switch)
                    .fixedSize()
                if draft.isDateLinked {
                    DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .fixedSize()
                } else {
                    Label("Saved without a calendar date", systemImage: "note.text")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            TextEditor(text: $draft.body)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(16)
                .background(HubPalette.grouped)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16).stroke(HubPalette.separator, lineWidth: 1)
                }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct NotesWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var selectedFolder: String?
    @State private var selectedSpaceID: String?
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
            .filter { selectedSpaceID == nil || $0.course.id == selectedSpaceID }
            .filter {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                return query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.markdown.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private var selectedSpace: Course? {
        guard let selectedSpaceID else { return nil }
        return appState.spaces.first(where: { $0.id == selectedSpaceID })
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
                Button {
                    _ = appState.addNote(
                        folder: selectedFolder ?? "Inbox",
                        course: selectedSpace ?? appState.defaultSpace
                    )
                } label: {
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
                    Button("All Spaces", systemImage: selectedSpaceID == nil ? "checkmark" : "rectangle.3.group") {
                        selectSpace(nil)
                    }
                    Divider()
                    ForEach(appState.spaces) { space in
                        Button(space.title, systemImage: selectedSpaceID == space.id ? "checkmark" : "circle.fill") {
                            selectSpace(space.id)
                        }
                    }
                } label: {
                    Label(selectedSpace?.title ?? "All Spaces", systemImage: "rectangle.3.group")
                        .font(.system(size: 12, weight: .semibold))
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif

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
            .filter { selectedSpaceID == nil || $0.course.id == selectedSpaceID }
            .sorted { $0.modifiedAt > $1.modifiedAt }
        if let first = candidates.first { appState.openNote(first.id) }
    }

    private func selectSpace(_ spaceID: String?) {
        selectedSpaceID = spaceID
        let candidates = appState.notes
            .filter { spaceID == nil || $0.course.id == spaceID }
            .filter { selectedFolder == nil || $0.folder == selectedFolder }
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
                        Text(note.course.title)
                        Text("·")
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
    @State private var targetHeadingLine: Int?
    @State private var markdownSelection = NSRange(location: 0, length: 0)
    @State private var autosaveTask: Task<Void, Never>?
    @State private var exportURLs: [URL] = []
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

                NoteFormattingBar(
                    onTool: { insert($0) },
                    onColor: { applyColor($0) }
                )
                .disabled(isReadingMode)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(HubPalette.sidebar)

            Divider()

            Group {
                if isReadingMode {
                    MarkdownReadingView(
                        source: draft.markdown,
                        targetLine: targetHeadingLine,
                        onToggleChecklist: toggleChecklist
                    )
                        .accessibilityLabel("Markdown reading view")
                } else {
                    ObsidianLiveMarkdownEditor(
                        text: $draft.markdown,
                        targetLine: targetHeadingLine,
                        selection: $markdownSelection,
                        onSelectionChange: { markdownSelection = $0 }
                    )
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
            Button("Export DOCX, PDF, RTF & CSV", systemImage: "square.and.arrow.up") {
                save(showStatus: false)
                exportURLs = appState.exportNote(draft)
            }
            if !exportURLs.isEmpty {
                Divider()
                ForEach(exportURLs, id: \.self) { url in
                    Button("Open \(url.lastPathComponent)", systemImage: "doc") {
                        OpenURLHelper.open(url)
                    }
                }
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
        let result = tool.applyingShortcut(to: draft.markdown, selection: markdownSelection)
        draft.markdown = result.text
        markdownSelection = result.selection
        isReadingMode = false
    }

    private func applyColor(_ color: MarkdownTextColor) {
        let result = MarkdownColorFormatting.applying(color, to: draft.markdown, selection: markdownSelection)
        draft.markdown = result.text
        markdownSelection = result.selection
        isReadingMode = false
    }

    private func toggleChecklist(_ line: Int) {
        guard let result = MarkdownChecklist.togglingLine(in: draft.markdown, lineNumber: line) else { return }
        draft.markdown = result.text
        markdownSelection = result.selection
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
    case strikethrough
    case underline
    case highlight
    case checklist
    case link
    case quote
    case code
    case table
    case divider

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heading: "Heading"
        case .bold: "Bold"
        case .italic: "Italic"
        case .strikethrough: "Strikethrough"
        case .underline: "Underline"
        case .highlight: "Highlight"
        case .checklist: "Checklist"
        case .link: "Link"
        case .quote: "Quote"
        case .code: "Code"
        case .table: "Table"
        case .divider: "Divider"
        }
    }

    var icon: String {
        switch self {
        case .heading: "textformat.size"
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .underline: "underline"
        case .highlight: "highlighter"
        case .checklist: "checklist"
        case .link: "link"
        case .quote: "text.quote"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .table: "tablecells"
        case .divider: "minus"
        }
    }

    var syntax: String {
        switch self {
        case .heading: "## Heading"
        case .bold: "**bold text**"
        case .italic: "*italic text*"
        case .strikethrough: "~~strikethrough~~"
        case .underline: "{{underline|underlined text}}"
        case .highlight: "==highlighted text=="
        case .checklist: "- [ ] task"
        case .link: "[label](https://example.com)"
        case .quote: "> quote"
        case .code: "`code`"
        case .table: "| Column 1 | Column 2 |\n| --- | --- |\n| Value | Value |"
        case .divider: "---"
        }
    }

    var snippet: String { syntax + "\n" }

    func applying(to source: String, selection: NSRange) -> MarkdownEditResult {
        let sourceLength = (source as NSString).length
        let location = selection.location == NSNotFound ? sourceLength : min(selection.location, sourceLength)
        let length = min(selection.length, sourceLength - location)
        let safeRange = NSRange(location: location, length: length)
        let selectedText = (source as NSString).substring(with: safeRange)

        let replacement: String
        if safeRange.length == 0 {
            replacement = snippet
        } else {
            switch self {
            case .heading:
                replacement = prefixLines(selectedText, with: "## ")
            case .bold:
                replacement = "**\(selectedText)**"
            case .italic:
                replacement = "*\(selectedText)*"
            case .strikethrough:
                replacement = "~~\(selectedText)~~"
            case .underline:
                replacement = "{{underline|\(selectedText)}}"
            case .highlight:
                replacement = "==\(selectedText)=="
            case .checklist:
                replacement = prefixLines(selectedText, with: "- [ ] ")
            case .link:
                replacement = "[\(selectedText)](https://example.com)"
            case .quote:
                replacement = prefixLines(selectedText, with: "> ")
            case .code:
                replacement = selectedText.contains("\n")
                    ? "```\n\(selectedText)\n```"
                    : "`\(selectedText)`"
            case .table:
                replacement = snippet
            case .divider:
                replacement = "\(selectedText)\n---\n"
            }
        }

        let mutable = NSMutableString(string: source)
        mutable.replaceCharacters(in: safeRange, with: replacement)
        return MarkdownEditResult(
            text: mutable as String,
            selection: NSRange(location: location + (replacement as NSString).length, length: 0)
        )
    }

    func applyingShortcut(to source: String, selection: NSRange) -> MarkdownEditResult {
        switch self {
        case .bold:
            return applyingInlineShortcut(marker: "**", to: source, selection: selection)
        case .italic:
            return applyingInlineShortcut(marker: "*", to: source, selection: selection)
        case .strikethrough:
            return applyingInlineShortcut(marker: "~~", to: source, selection: selection)
        case .underline:
            return applyingAsymmetricShortcut(
                opening: "{{underline|",
                closing: "}}",
                placeholder: "underlined text",
                to: source,
                selection: selection
            )
        case .highlight:
            return applyingInlineShortcut(marker: "==", to: source, selection: selection)
        case .code:
            return applyingInlineShortcut(marker: "`", to: source, selection: selection)
        case .link:
            let sourceString = source as NSString
            let location = selection.location == NSNotFound ? sourceString.length : min(selection.location, sourceString.length)
            let length = min(selection.length, sourceString.length - location)
            let range = NSRange(location: location, length: length)
            let label = length == 0 ? "link" : sourceString.substring(with: range)
            let destination = "https://example.com"
            let replacement = "[\(label)](\(destination))"
            let mutable = NSMutableString(string: source)
            mutable.replaceCharacters(in: range, with: replacement)
            return MarkdownEditResult(
                text: mutable as String,
                selection: NSRange(location: location + 1, length: (label as NSString).length)
            )
        default:
            return applying(to: source, selection: selection)
        }
    }

    private func applyingInlineShortcut(marker: String, to source: String, selection: NSRange) -> MarkdownEditResult {
        let sourceString = source as NSString
        let markerLength = (marker as NSString).length
        let location = selection.location == NSNotFound ? sourceString.length : min(selection.location, sourceString.length)
        let length = min(selection.length, sourceString.length - location)
        let range = NSRange(location: location, length: length)
        let selected = sourceString.substring(with: range)
        let mutable = NSMutableString(string: source)

        if length == 0 {
            mutable.insert(marker + marker, at: location)
            return MarkdownEditResult(
                text: mutable as String,
                selection: NSRange(location: location + markerLength, length: 0)
            )
        }

        if selected.hasPrefix(marker), selected.hasSuffix(marker), length >= markerLength * 2 {
            let innerRange = NSRange(location: markerLength, length: length - markerLength * 2)
            let inner = (selected as NSString).substring(with: innerRange)
            mutable.replaceCharacters(in: range, with: inner)
            return MarkdownEditResult(
                text: mutable as String,
                selection: NSRange(location: location, length: (inner as NSString).length)
            )
        }

        if location >= markerLength, NSMaxRange(range) + markerLength <= sourceString.length {
            let before = sourceString.substring(with: NSRange(location: location - markerLength, length: markerLength))
            let after = sourceString.substring(with: NSRange(location: NSMaxRange(range), length: markerLength))
            if before == marker, after == marker {
                mutable.replaceCharacters(
                    in: NSRange(location: location - markerLength, length: length + markerLength * 2),
                    with: selected
                )
                return MarkdownEditResult(
                    text: mutable as String,
                    selection: NSRange(location: location - markerLength, length: length)
                )
            }
        }

        mutable.replaceCharacters(in: range, with: marker + selected + marker)
        return MarkdownEditResult(
            text: mutable as String,
            selection: NSRange(location: location + markerLength, length: length)
        )
    }

    private func applyingAsymmetricShortcut(
        opening: String,
        closing: String,
        placeholder: String,
        to source: String,
        selection: NSRange
    ) -> MarkdownEditResult {
        let sourceString = source as NSString
        let openingLength = (opening as NSString).length
        let closingLength = (closing as NSString).length
        let location = selection.location == NSNotFound ? sourceString.length : min(selection.location, sourceString.length)
        let length = min(selection.length, sourceString.length - location)
        let range = NSRange(location: location, length: length)
        let selected = length == 0 ? placeholder : sourceString.substring(with: range)
        let mutable = NSMutableString(string: source)

        if length > 0,
           location >= openingLength,
           NSMaxRange(range) + closingLength <= sourceString.length,
           sourceString.substring(with: NSRange(location: location - openingLength, length: openingLength)) == opening,
           sourceString.substring(with: NSRange(location: NSMaxRange(range), length: closingLength)) == closing {
            mutable.replaceCharacters(
                in: NSRange(location: location - openingLength, length: length + openingLength + closingLength),
                with: selected
            )
            return MarkdownEditResult(
                text: mutable as String,
                selection: NSRange(location: location - openingLength, length: length)
            )
        }

        let replacement = opening + selected + closing
        mutable.replaceCharacters(in: range, with: replacement)
        return MarkdownEditResult(
            text: mutable as String,
            selection: NSRange(location: location + openingLength, length: (selected as NSString).length)
        )
    }

    private func prefixLines(_ text: String, with prefix: String) -> String {
        text.components(separatedBy: .newlines)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }
}

struct MarkdownEditResult: Equatable {
    let text: String
    let selection: NSRange
}

enum MarkdownChecklist {
    private static let pattern = #"^(\s*[-*+]\s+\[)([ xX])(\]\s+)(.*)$"#

    static func togglingLine(in source: String, lineNumber: Int) -> MarkdownEditResult? {
        let sourceString = source as NSString
        var cursor = 0
        var currentLine = 0
        while cursor <= sourceString.length {
            let range = sourceString.lineRange(for: NSRange(location: min(cursor, sourceString.length), length: 0))
            if currentLine == lineNumber { return toggling(in: source, lineRange: range, requireHitAt: nil) }
            guard NSMaxRange(range) > cursor, NSMaxRange(range) < sourceString.length else { break }
            cursor = NSMaxRange(range)
            currentLine += 1
        }
        return nil
    }

    static func togglingMarker(in source: String, characterIndex: Int) -> MarkdownEditResult? {
        let sourceString = source as NSString
        guard characterIndex >= 0, characterIndex <= sourceString.length else { return nil }
        let lineRange = sourceString.lineRange(for: NSRange(location: min(characterIndex, sourceString.length), length: 0))
        return toggling(in: source, lineRange: lineRange, requireHitAt: characterIndex)
    }

    private static func toggling(
        in source: String,
        lineRange: NSRange,
        requireHitAt characterIndex: Int?
    ) -> MarkdownEditResult? {
        let sourceString = source as NSString
        let contentRange = NSRange(
            location: lineRange.location,
            length: max(0, min(NSMaxRange(lineRange), sourceString.length) - lineRange.location)
        )
        let line = sourceString.substring(with: contentRange).trimmingCharacters(in: .newlines)
        let lineString = line as NSString
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: line,
                range: NSRange(location: 0, length: lineString.length)
              ) else { return nil }

        if let characterIndex {
            let marker = match.range(at: 1)
            let globalMarker = NSRange(location: contentRange.location + marker.location, length: marker.length + 2)
            guard NSLocationInRange(characterIndex, globalMarker) else { return nil }
        }

        let stateRange = match.range(at: 2)
        let state = lineString.substring(with: stateRange)
        let replacement = state == " " ? "x" : " "
        let globalState = NSRange(location: contentRange.location + stateRange.location, length: stateRange.length)
        let mutable = NSMutableString(string: source)
        mutable.replaceCharacters(in: globalState, with: replacement)
        return MarkdownEditResult(
            text: mutable as String,
            selection: NSRange(location: NSMaxRange(globalState), length: 0)
        )
    }
}

struct MarkdownTextColor: Identifiable, Hashable {
    let name: String
    let hex: UInt32?
    var id: String { hex.map { String(format: "%06X", $0) } ?? "automatic" }
    var color: Color { hex.map(Course.color(for:)) ?? .primary }

    static let palette: [MarkdownTextColor] = [
        MarkdownTextColor(name: "Automatic", hex: nil),
        MarkdownTextColor(name: "Red", hex: 0xDC3545),
        MarkdownTextColor(name: "Orange", hex: 0xE67E22),
        MarkdownTextColor(name: "Gold", hex: 0xB7791F),
        MarkdownTextColor(name: "Green", hex: 0x238636),
        MarkdownTextColor(name: "Teal", hex: 0x138A8A),
        MarkdownTextColor(name: "Blue", hex: 0x2563EB),
        MarkdownTextColor(name: "Purple", hex: 0x7C3AED),
        MarkdownTextColor(name: "Pink", hex: 0xC02670),
        MarkdownTextColor(name: "Gray", hex: 0x667085)
    ]

    static func custom(_ color: Color) -> MarkdownTextColor? {
        #if os(macOS)
        guard let native = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        #else
        let native = UIColor(color)
        #endif
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #if os(macOS)
        native.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        guard native.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        #endif
        let value = UInt32((red * 255).rounded()) << 16
            | UInt32((green * 255).rounded()) << 8
            | UInt32((blue * 255).rounded())
        return MarkdownTextColor(name: "Custom", hex: value)
    }
}

enum MarkdownColorFormatting {
    static let pattern = #"\{\{color:#([0-9A-Fa-f]{6})\|(.+?)\}\}"#

    static func applying(_ color: MarkdownTextColor, to source: String, selection: NSRange) -> MarkdownEditResult {
        let sourceString = source as NSString
        let location = selection.location == NSNotFound ? sourceString.length : min(selection.location, sourceString.length)
        let length = min(selection.length, sourceString.length - location)
        let range = NSRange(location: location, length: length)
        let expression = try! NSRegularExpression(pattern: pattern)

        if length > 0,
           let enclosing = expression.matches(in: source, range: NSRange(location: 0, length: sourceString.length)).first(where: {
               let content = $0.range(at: 2)
               return content.location <= range.location && NSMaxRange(range) <= NSMaxRange(content)
           }) {
            let contentRange = enclosing.range(at: 2)
            let oldHex = sourceString.substring(with: enclosing.range(at: 1)).uppercased()
            let before = sourceString.substring(with: NSRange(
                location: contentRange.location,
                length: range.location - contentRange.location
            ))
            let selected = sourceString.substring(with: range)
            let after = sourceString.substring(with: NSRange(
                location: NSMaxRange(range),
                length: NSMaxRange(contentRange) - NSMaxRange(range)
            ))
            let beforePiece = wrap(before, hex: oldHex)
            let selectedPiece = wrap(selected, hex: color.hexString)
            let afterPiece = wrap(after, hex: oldHex)
            let replacement = beforePiece + selectedPiece + afterPiece
            let mutable = NSMutableString(string: source)
            mutable.replaceCharacters(in: enclosing.range, with: replacement)
            return MarkdownEditResult(
                text: mutable as String,
                selection: NSRange(
                    location: enclosing.range.location + (beforePiece as NSString).length + openingLength(for: color.hexString),
                    length: (selected as NSString).length
                )
            )
        }

        if length == 0 {
            guard let hex = color.hexString else {
                return MarkdownEditResult(text: source, selection: range)
            }
            let placeholder = "colored text"
            let replacement = wrap(placeholder, hex: hex)
            let mutable = NSMutableString(string: source)
            mutable.insert(replacement, at: location)
            return MarkdownEditResult(
                text: mutable as String,
                selection: NSRange(location: location + openingLength(for: hex), length: (placeholder as NSString).length)
            )
        }

        let selected = sourceString.substring(with: range)
        let plainSelection = removingMarkup(from: selected)
        let replacement = wrap(plainSelection, hex: color.hexString)
        let mutable = NSMutableString(string: source)
        mutable.replaceCharacters(in: range, with: replacement)
        return MarkdownEditResult(
            text: mutable as String,
            selection: NSRange(
                location: location + openingLength(for: color.hexString),
                length: (plainSelection as NSString).length
            )
        )
    }

    static func attributedString(from source: String) -> AttributedString {
        customAttributedString(from: source)
    }

    private enum InlineStyle {
        case color(UInt32)
        case underline
        case highlight
        case strikethrough
    }

    private struct InlineMatch {
        let range: NSRange
        let content: String
        let style: InlineStyle
    }

    private static func customAttributedString(from source: String) -> AttributedString {
        let sourceString = source as NSString
        let candidates: [InlineMatch] = [
            firstInlineMatch(pattern, contentGroup: 2, in: source).map { match in
                let hex = UInt32(sourceString.substring(with: match.range(at: 1)), radix: 16) ?? 0x20242B
                return InlineMatch(
                    range: match.range,
                    content: sourceString.substring(with: match.range(at: 2)),
                    style: .color(hex)
                )
            },
            firstInlineMatch(#"\{\{underline\|(.+?)\}\}"#, contentGroup: 1, in: source).map { match in
                InlineMatch(range: match.range, content: sourceString.substring(with: match.range(at: 1)), style: .underline)
            },
            firstInlineMatch(#"==(.+?)=="#, contentGroup: 1, in: source).map { match in
                InlineMatch(range: match.range, content: sourceString.substring(with: match.range(at: 1)), style: .highlight)
            },
            firstInlineMatch(#"~~(.+?)~~"#, contentGroup: 1, in: source).map { match in
                InlineMatch(range: match.range, content: sourceString.substring(with: match.range(at: 1)), style: .strikethrough)
            }
        ].compactMap { $0 }

        guard let match = candidates.min(by: {
            $0.range.location == $1.range.location
                ? $0.range.length > $1.range.length
                : $0.range.location < $1.range.location
        }) else { return markdown(source) }

        var result = AttributedString()
        if match.range.location > 0 {
            result += markdown(sourceString.substring(to: match.range.location))
        }
        var styled = customAttributedString(from: match.content)
        switch match.style {
        case .color(let hex): styled.foregroundColor = Course.color(for: hex)
        case .underline: styled.underlineStyle = .single
        case .highlight: styled.backgroundColor = Color.yellow.opacity(0.42)
        case .strikethrough: styled.strikethroughStyle = .single
        }
        result += styled
        if NSMaxRange(match.range) < sourceString.length {
            result += customAttributedString(from: sourceString.substring(from: NSMaxRange(match.range)))
        }
        return result
    }

    private static func firstInlineMatch(
        _ pattern: String,
        contentGroup: Int,
        in source: String
    ) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let match = expression.firstMatch(
            in: source,
            range: NSRange(location: 0, length: (source as NSString).length)
        )
        guard let match, match.range(at: contentGroup).location != NSNotFound else { return nil }
        return match
    }

    private static func markdown(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source)) ?? AttributedString(source)
    }

    private static func wrap(_ text: String, hex: String?) -> String {
        guard !text.isEmpty else { return "" }
        guard let hex else { return text }
        return "{{color:#\(hex)|\(text)}}"
    }

    private static func openingLength(for hex: String?) -> Int {
        guard let hex else { return 0 }
        return ("{{color:#\(hex)|" as NSString).length
    }

    private static func removingMarkup(from source: String) -> String {
        let expression = try! NSRegularExpression(pattern: pattern)
        let mutable = NSMutableString(string: source)
        for match in expression.matches(
            in: source,
            range: NSRange(location: 0, length: (source as NSString).length)
        ).reversed() {
            mutable.replaceCharacters(in: match.range, with: (source as NSString).substring(with: match.range(at: 2)))
        }
        return mutable as String
    }
}

private extension MarkdownTextColor {
    var hexString: String? { hex.map { String(format: "%06X", $0) } }
}

struct NoteFormattingBar: View {
    let onTool: (MarkdownTool) -> Void
    let onColor: (MarkdownTextColor) -> Void
    @State private var customColor: Color = .blue

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Menu {
                    Button("Heading", systemImage: "textformat.size") { onTool(.heading) }
                    Button("Quote", systemImage: "text.quote") { onTool(.quote) }
                    Button("Code", systemImage: "chevron.left.forwardslash.chevron.right") { onTool(.code) }
                    Button("Divider", systemImage: "minus") { onTool(.divider) }
                } label: {
                    Label("Style", systemImage: "textformat.size")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                }
                .menuStyle(.borderlessButton)

                barDivider
                toolButton(.bold, shortcut: "⌘B")
                toolButton(.italic, shortcut: "⌘I")
                toolButton(.underline)
                toolButton(.strikethrough)
                toolButton(.highlight)
                barDivider

                Menu {
                    ForEach(MarkdownTextColor.palette) { color in
                        Button { onColor(color) } label: {
                            Label {
                                Text(color.name)
                            } icon: {
                                Image(systemName: color.hex == nil ? "a.circle" : "circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(color.color)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "textformat")
                        .foregroundStyle(HubPalette.hubAccent)
                        .frame(width: 30, height: 30)
                }
                .menuStyle(.borderlessButton)
                .help("Text color")

                ColorPicker("Custom text color", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28, height: 28)
                    .onChange(of: customColor) { _, value in
                        if let color = MarkdownTextColor.custom(value) { onColor(color) }
                    }

                barDivider
                toolButton(.checklist)
                toolButton(.link, shortcut: "⌘K")
                toolButton(.table)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 40)
        .background(HubPalette.grouped)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(HubPalette.separator, lineWidth: 1) }
        .accessibilityLabel("Note formatting toolbar")
    }

    private func toolButton(_ tool: MarkdownTool, shortcut: String? = nil) -> some View {
        Button { onTool(tool) } label: {
            Image(systemName: tool.icon).frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .help(shortcut.map { "\(tool.title) \($0)" } ?? tool.title)
        .accessibilityLabel(tool.title)
    }

    private var barDivider: some View {
        Rectangle().fill(HubPalette.separator).frame(width: 1, height: 20).padding(.horizontal, 3)
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
    var onToggleChecklist: ((Int) -> Void)? = nil

    private var lines: [(offset: Int, element: String)] {
        Array(source.components(separatedBy: .newlines).enumerated())
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    ForEach(lines, id: \.offset) { line in
                        markdownLine(line.element, lineNumber: line.offset).id(line.offset)
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
    private func markdownLine(_ source: String, lineNumber: Int) -> some View {
        let hashes = source.prefix(while: { $0 == "#" }).count
        if (1...6).contains(hashes), source.dropFirst(hashes).first == " " {
            Text(MarkdownColorFormatting.attributedString(
                from: source.dropFirst(hashes).trimmingCharacters(in: .whitespacesAndNewlines)
            ))
                .font(hashes == 1 ? .title2.bold() : (hashes == 2 ? .headline : .subheadline.bold()))
                .padding(.top, hashes == 1 ? 8 : 4)
        } else if source.isEmpty {
            Color.clear.frame(height: 4)
        } else if let checklist = checklistInfo(source) {
            Button { onToggleChecklist?(lineNumber) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: checklist.checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checklist.checked ? HubPalette.hubAccent : HubPalette.secondaryText)
                    Text(MarkdownColorFormatting.attributedString(from: checklist.content))
                        .strikethrough(checklist.checked)
                        .foregroundStyle(checklist.checked ? HubPalette.secondaryText : Color.primary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onToggleChecklist == nil)
        } else {
            Text(MarkdownColorFormatting.attributedString(from: source))
                .font(.system(size: 14))
        }
    }

    private func checklistInfo(_ line: String) -> (checked: Bool, content: String)? {
        let expression = try? NSRegularExpression(pattern: #"^\s*[-*+]\s+\[([ xX])\]\s+(.*)$"#)
        let lineString = line as NSString
        guard let match = expression?.firstMatch(
            in: line,
            range: NSRange(location: 0, length: lineString.length)
        ) else { return nil }
        let state = lineString.substring(with: match.range(at: 1))
        return (state.lowercased() == "x", lineString.substring(with: match.range(at: 2)))
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

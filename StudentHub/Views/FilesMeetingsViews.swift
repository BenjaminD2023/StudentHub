import SwiftUI
import UniformTypeIdentifiers

struct FilesWorkspaceView: View {
    private enum Collection: String, CaseIterable, Identifiable {
        case all = "All files"
        case recent = "Recent"
        case pdf = "PDFs"
        case image = "Images"
        case document = "Documents"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .all: "tray.full"
            case .recent: "clock"
            case .pdf: "doc.richtext"
            case .image: "photo"
            case .document: "doc.text"
            }
        }
    }

    private enum Layout: String, CaseIterable, Identifiable {
        case grid
        case list
        var id: String { rawValue }
    }

    private enum Sort: String, CaseIterable, Identifiable {
        case newest = "Newest first"
        case oldest = "Oldest first"
        case name = "Name"
        var id: String { rawValue }
    }

    @EnvironmentObject private var appState: AppState
    @State private var isImporting = false
    @State private var collection: Collection = .all
    @State private var selectedCourse: Course?
    @State private var searchText = ""
    @State private var layout: Layout = .grid
    @State private var sort: Sort = .newest

    private var visibleFiles: [HubFileItem] {
        var result = appState.files.filter { item in
            if let selectedCourse, item.course != selectedCourse { return false }
            switch collection {
            case .all: break
            case .recent:
                guard item.addedAt >= (Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast) else { return false }
            case .pdf:
                guard item.kind == .pdf else { return false }
            case .image:
                guard item.kind == .image else { return false }
            case .document:
                guard item.kind == .document else { return false }
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty || item.displayName.localizedCaseInsensitiveContains(query) || item.annotationNotes.localizedCaseInsensitiveContains(query)
        }
        switch sort {
        case .newest: result.sort { $0.addedAt > $1.addedAt }
        case .oldest: result.sort { $0.addedAt < $1.addedAt }
        case .name: result.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        return result
    }

    private var collectionTitle: String {
        selectedCourse?.title ?? collection.rawValue
    }

    var body: some View {
        HStack(spacing: 0) {
            librarySidebar
            Divider()
            fileBrowser

            if let item = appState.selectedFile {
                Divider()
                FileInspectorView(item: item)
                    .id(item.id)
                    .frame(width: 390)
            }
        }
        .background(HubPalette.background)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): urls.forEach(appState.importFile)
            case .failure(let error): appState.statusMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private var librarySidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LIBRARY")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(HubPalette.secondaryText)
                    Text("Files")
                        .font(.title3.bold())
                }
                Spacer()
                Button { isImporting = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .help("Import files")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HubPalette.secondaryText)
                TextField("Search files", text: $searchText)
                    .textFieldStyle(.plain)
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

            VStack(alignment: .leading, spacing: 4) {
                sidebarLabel("SMART COLLECTIONS")
                ForEach(Collection.allCases) { item in
                    Button {
                        collection = item
                        selectedCourse = nil
                    } label: {
                        libraryRow(
                            icon: item.icon,
                            label: item.rawValue,
                            count: count(for: item),
                            isSelected: selectedCourse == nil && collection == item
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                sidebarLabel("COURSE FOLDERS")
                ForEach(appState.spaces) { course in
                    Button {
                        collection = .all
                        selectedCourse = course
                    } label: {
                        libraryRow(
                            icon: "folder.fill",
                            label: course.title,
                            count: appState.files.filter { $0.course == course }.count,
                            isSelected: selectedCourse == course,
                            accent: course.accent
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
            Button {
                OpenURLHelper.reveal(WorkspaceStorage.filesURL)
            } label: {
                Label("Open Library folder", systemImage: "folder")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Reveal local Student Hub files in Finder")
        }
        .padding(16)
        .frame(width: 226)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(HubPalette.sidebar)
    }

    private var fileBrowser: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(collectionTitle)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("\(visibleFiles.count) item\(visibleFiles.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(HubPalette.secondaryText)
                }
                Spacer()
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases) { option in Text(option.rawValue).tag(option) }
                    }
                } label: {
                    Label(sort.rawValue, systemImage: "arrow.up.arrow.down")
                }
                .buttonStyle(.bordered)
                Picker("Layout", selection: $layout) {
                    Image(systemName: "square.grid.2x2").tag(Layout.grid)
                    Image(systemName: "list.bullet").tag(Layout.list)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 76)
                Button { isImporting = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(HubProminentButtonStyle())
            }
            .padding(20)

            Divider()

            if visibleFiles.isEmpty {
                HubEmptyState(
                    icon: searchText.isEmpty ? "doc.badge.plus" : "magnifyingglass",
                    title: searchText.isEmpty ? "Nothing here yet" : "No matching files",
                    message: searchText.isEmpty ? "Import a PDF, image, or document. It stays in your local Student Hub library." : "Try another search or choose All files."
                )
            } else if layout == .grid {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(visibleFiles) { item in fileCard(item) }
                    }
                    .padding(20)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(visibleFiles) { item in fileListRow(item) }
                    }
                    .padding(14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HubPalette.background)
    }

    private func sidebarLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(HubPalette.secondaryText)
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
    }

    private func libraryRow(icon: String, label: String, count: Int, isSelected: Bool, accent: Color = HubPalette.hubAccent) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(isSelected ? accent : HubPalette.secondaryText)
            Text(label).lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(HubPalette.secondaryText)
        }
        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(isSelected ? HubPalette.selected : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private func count(for item: Collection) -> Int {
        switch item {
        case .all: appState.files.count
        case .recent: appState.files.filter { $0.addedAt >= (Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast) }.count
        case .pdf: appState.files.filter { $0.kind == .pdf }.count
        case .image: appState.files.filter { $0.kind == .image }.count
        case .document: appState.files.filter { $0.kind == .document }.count
        }
    }

    private func fileCard(_ item: HubFileItem) -> some View {
        Button {
            appState.selectedFileID = item.id
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(item.course.accent.opacity(0.12))
                    Image(systemName: fileIcon(item.kind))
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(item.kind == .pdf ? HubPalette.red : item.course.accent)
                }
                .frame(height: 105)
                Text(item.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack {
                    Text(item.course.title)
                    Spacer()
                    Text(item.kind.rawValue.uppercased())
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(HubPalette.secondaryText)
            }
            .padding(12)
            .background(appState.selectedFileID == item.id ? HubPalette.selected : HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).stroke(HubPalette.separator, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { OpenURLHelper.open(WorkspaceStorage.fileURL(for: item)) }
            Button("Reveal in Finder") { OpenURLHelper.reveal(WorkspaceStorage.fileURL(for: item)) }
        }
    }

    private func fileListRow(_ item: HubFileItem) -> some View {
        Button { appState.selectedFileID = item.id } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(item.course.accent.opacity(0.12))
                    Image(systemName: fileIcon(item.kind))
                        .foregroundStyle(item.kind == .pdf ? HubPalette.red : item.course.accent)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("\(item.course.title) · Added \(item.addedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(HubPalette.secondaryText)
                }
                Spacer()
                Text(item.kind.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(HubPalette.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(HubPalette.secondaryText)
            }
            .padding(.horizontal, 11)
            .frame(minHeight: 58)
            .background(appState.selectedFileID == item.id ? HubPalette.selected : HubPalette.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).stroke(HubPalette.separator, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func fileIcon(_ kind: HubFileItem.Kind) -> String {
        switch kind {
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .document: "doc.text"
        case .other: "doc"
        }
    }
}

struct FileInspectorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft: HubFileItem

    init(item: HubFileItem) {
        _draft = State(initialValue: item)
    }

    private var fileURL: URL { WorkspaceStorage.fileURL(for: draft) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("File name", text: $draft.displayName)
                    .font(.system(size: 15, weight: .bold))
                    .textFieldStyle(.plain)
                Button { appState.selectedFileID = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
            }
            HStack {
                Picker("Course", selection: $draft.course) {
                    ForEach(appState.spaces) { course in Text(course.title).tag(course) }
                }
                .labelsHidden()
                Spacer()
                Button("Open") { OpenURLHelper.open(fileURL) }
                    .buttonStyle(.bordered)
                Button("Reveal") { OpenURLHelper.reveal(fileURL) }
                    .buttonStyle(.bordered)
            }

            if draft.kind == .pdf {
                PDFDocumentView(url: fileURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(HubPalette.separator, lineWidth: 1) }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(HubPalette.grouped)
                    VStack(spacing: 10) {
                        Image(systemName: "doc").font(.system(size: 38)).foregroundStyle(HubPalette.secondaryText)
                        Text("Open this file in its default editor")
                            .font(.system(size: 12))
                            .foregroundStyle(HubPalette.secondaryText)
                    }
                }
                .frame(maxHeight: 220)
            }

            Text("ANNOTATION NOTE")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(HubPalette.secondaryText)
            TextEditor(text: $draft.annotationNotes)
                .font(.system(size: 12))
                .frame(height: 82)
                .padding(6)
                .background(HubPalette.grouped)
                .clipShape(RoundedRectangle(cornerRadius: 9))

            HStack {
                Button("Save details") {
                    appState.updateFile(draft)
                    appState.statusMessage = "File details saved"
                }
                .buttonStyle(HubProminentButtonStyle())
                if draft.kind == .pdf {
                    Button("Place note on PDF") {
                        do {
                            try PDFAnnotationService.addFreeText(draft.annotationNotes.isEmpty ? "Student Hub note" : draft.annotationNotes, to: fileURL)
                            appState.updateFile(draft)
                            appState.statusMessage = "PDF annotation added"
                        } catch {
                            appState.statusMessage = "Annotation failed: \(error.localizedDescription)"
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button("Delete", role: .destructive) { appState.deleteFile(draft.id) }
            }
        }
        .padding(18)
        .background(HubPalette.sidebar)
    }
}

struct MeetingsWorkspaceView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Meetings").font(.system(size: 19, weight: .bold))
                    Spacer()
                    Button {
                        appState.addMeeting(title: "New meeting", projectID: appState.selectedProjectID)
                    } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                }
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(appState.meetings.sorted { $0.date > $1.date }) { meeting in
                            Button {
                                appState.selectedMeetingID = meeting.id
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(meeting.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    HStack {
                                        Text(meeting.date.formatted(date: .abbreviated, time: .shortened))
                                        Spacer()
                                        if let recurrence = meeting.recurrence {
                                            Image(systemName: "repeat")
                                                .help(recurrence.title)
                                        }
                                        if !meeting.summary.isEmpty { Image(systemName: "sparkles") }
                                    }
                                    .font(.system(size: 9))
                                    .foregroundStyle(HubPalette.secondaryText)
                                }
                                .padding(11)
                                .background(appState.selectedMeetingID == meeting.id ? HubPalette.selected : HubPalette.grouped)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18)
            .frame(width: 270)
            .background(HubPalette.sidebar)
            Divider()
            if let meeting = appState.selectedMeeting {
                MeetingEditor(meeting: meeting)
                    .id(meeting.id)
            } else {
                HubEmptyState(icon: "person.2", title: "No meeting selected", message: "Create a record for a project discussion or study-group session.")
            }
        }
        .background(HubPalette.background)
    }
}

struct MeetingEditor: View {
    @EnvironmentObject private var appState: AppState
    @State private var draft: MeetingRecord

    init(meeting: MeetingRecord) {
        _draft = State(initialValue: meeting)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                HubPageHeader(eyebrow: "Project record", title: "Meeting notes", subtitle: "Lines beginning with TODO: or - [ ] become project tasks.")
                Spacer()
                Button("Save", action: save).buttonStyle(.bordered)
                Button {
                    save()
                    appState.generateMeetingSummary(draft.id)
                    if let refreshed = appState.meetings.first(where: { $0.id == draft.id }) { draft = refreshed }
                    appState.statusMessage = "Summary and action tasks generated"
                } label: {
                    Label("Summarize", systemImage: "sparkles")
                }
                .buttonStyle(HubProminentButtonStyle())
            }

            HStack {
                TextField("Meeting title", text: $draft.title)
                    .font(.system(size: 18, weight: .bold))
                    .textFieldStyle(.plain)
                    .onSubmit(save)
                DatePicker("", selection: $draft.date).labelsHidden()
                HubRecurrencePicker(selection: $draft.recurrence)
                    .labelsHidden()
                    .frame(width: 130)
                Picker("Project", selection: $draft.projectID) {
                    Text("No project").tag(Optional<UUID>.none)
                    ForEach(appState.projects) { project in Text(project.title).tag(Optional(project.id)) }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    HubSectionTitle(title: "Transcript / raw notes")
                    TextEditor(text: $draft.transcript)
                        .font(.system(size: 12))
                        .padding(8)
                        .background(HubPalette.grouped)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                VStack(alignment: .leading, spacing: 7) {
                    HubSectionTitle(title: "Summary", trailing: "editable")
                    TextEditor(text: $draft.summary)
                        .font(.system(size: 12))
                        .padding(8)
                        .background(HubPalette.grouped)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxHeight: .infinity)

            if !draft.actionTaskIDs.isEmpty {
                HubSectionTitle(title: "Action tasks", trailing: "\(draft.actionTaskIDs.count)")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(draft.actionTaskIDs, id: \.self) { taskID in
                            if let task = appState.tasks.first(where: { $0.id == taskID }) {
                                Button(task.title) {
                                    appState.selectedTaskID = taskID
                                    appState.navigate(to: .tasks)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Delete meeting", role: .destructive) { appState.deleteMeeting(draft.id) }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear { appState.updateMeeting(draft) }
    }

    private func save() {
        appState.updateMeeting(draft)
        appState.statusMessage = "Meeting saved"
    }
}

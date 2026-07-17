import Foundation

enum WorkspaceStorage {
    static var applicationSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("StudentHub", isDirectory: true)
    }

    static var databaseURL: URL {
        applicationSupportURL.appendingPathComponent("workspace.json")
    }

    static var libraryURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Student Hub Library", isDirectory: true)
    }

    static var notesURL: URL { libraryURL.appendingPathComponent("Notes", isDirectory: true) }
    static var filesURL: URL { libraryURL.appendingPathComponent("Files", isDirectory: true) }
    static var exportsURL: URL { libraryURL.appendingPathComponent("Exports", isDirectory: true) }

    static func prepareDirectories() throws {
        for url in [applicationSupportURL, libraryURL, notesURL, filesURL, exportsURL] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func load() -> WorkspaceSnapshot? {
        guard let data = try? Data(contentsOf: databaseURL) else { return nil }
        return decode(data)
    }

    static func encode(_ snapshot: WorkspaceSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) -> WorkspaceSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WorkspaceSnapshot.self, from: data)
    }

    static func save(_ snapshot: WorkspaceSnapshot) throws {
        try prepareDirectories()
        let data = try encode(snapshot)
        try data.write(to: databaseURL, options: .atomic)
    }

    static func writeMarkdown(_ note: HubNote) throws -> URL {
        try prepareDirectories()
        let folder = notesURL.appendingPathComponent(safeFileName(note.folder), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = markdownURL(for: note)
        let frontmatter = """
        ---
        id: \(note.id.uuidString)
        course: \(note.course.rawValue)
        modified: \(ISO8601DateFormatter().string(from: note.modifiedAt))
        ---

        """
        try (frontmatter + note.markdown).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func markdownURL(for note: HubNote) -> URL {
        notesURL
            .appendingPathComponent(safeFileName(note.folder), isDirectory: true)
            .appendingPathComponent(safeFileName(note.title))
            .appendingPathExtension("md")
    }

    static func importFile(from source: URL) throws -> HubFileItem {
        try prepareDirectories()
        let id = UUID()
        let storedName = "\(id.uuidString)-\(safeFileName(source.lastPathComponent))"
        let destination = filesURL.appendingPathComponent(storedName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        let ext = source.pathExtension.lowercased()
        let kind: HubFileItem.Kind
        if ext == "pdf" { kind = .pdf }
        else if ["png", "jpg", "jpeg", "heic"].contains(ext) { kind = .image }
        else if ["md", "txt", "doc", "docx", "pages"].contains(ext) { kind = .document }
        else { kind = .other }
        return HubFileItem(
            id: id,
            displayName: source.lastPathComponent,
            storedFileName: storedName,
            kind: kind
        )
    }

    static func fileURL(for item: HubFileItem) -> URL {
        filesURL.appendingPathComponent(item.storedFileName)
    }

    static func export(tasks: [HubTask], projects: [HubProject]) throws -> [URL] {
        try prepareDirectories()
        let formatter = ISO8601DateFormatter()
        let stamp = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let csvURL = exportsURL.appendingPathComponent("StudentHub-\(stamp).csv")
        let mdURL = exportsURL.appendingPathComponent("StudentHub-\(stamp).md")

        var csv = "Title,Course,Due,Completed,Project\n"
        for task in tasks {
            let project = projects.first(where: { $0.id == task.projectID })?.title ?? ""
            csv += [task.title, task.course.title, formatter.string(from: task.dueDate), String(task.isCompleted), project]
                .map(csvEscape)
                .joined(separator: ",") + "\n"
        }

        var markdown = "# Student Hub Export\n\nGenerated \(Date().formatted(date: .long, time: .shortened))\n\n"
        for project in projects where !project.isArchived {
            markdown += "## \(project.title)\n\nDeadline: \(project.deadline.formatted(date: .abbreviated, time: .omitted))\n\n"
            let projectTasks = tasks.filter { $0.projectID == project.id }
            for task in projectTasks {
                markdown += "- [\(task.isCompleted ? "x" : " ")] \(task.title) — \(task.dueDate.formatted(date: .abbreviated, time: .shortened))\n"
            }
            markdown += "\n"
        }
        markdown += "## Unassigned tasks\n\n"
        for task in tasks where task.projectID == nil {
            markdown += "- [\(task.isCompleted ? "x" : " ")] \(task.title) — \(task.dueDate.formatted(date: .abbreviated, time: .shortened))\n"
        }

        try csv.write(to: csvURL, atomically: true, encoding: .utf8)
        try markdown.write(to: mdURL, atomically: true, encoding: .utf8)
        return [csvURL, mdURL]
    }

    private static func safeFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return value.components(separatedBy: invalid).joined(separator: "-")
    }

    private static func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

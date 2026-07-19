import Foundation
import CoreGraphics
import CoreText
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum WorkspaceStorage {
    private static var storageName: String {
        #if DEBUG
        "StudentHub-Debug"
        #else
        "StudentHub"
        #endif
    }

    private static var libraryName: String {
        #if DEBUG
        "Student Hub Debug Library"
        #else
        "Student Hub Library"
        #endif
    }

    static var applicationSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(storageName, isDirectory: true)
    }

    static var databaseURL: URL {
        applicationSupportURL.appendingPathComponent("workspace.json")
    }

    static var libraryURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(libraryName, isDirectory: true)
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

    static func export(note: HubNote) throws -> [URL] {
        try prepareDirectories()
        let baseName = safeFileName(note.title.isEmpty ? "Untitled note" : note.title)
        let rtfURL = exportsURL.appendingPathComponent(baseName).appendingPathExtension("rtf")
        let pdfURL = exportsURL.appendingPathComponent(baseName).appendingPathExtension("pdf")
        let csvURL = exportsURL.appendingPathComponent(baseName + "-tables").appendingPathExtension("csv")
        let attributed = attributedDocument(for: note)

        let rtf = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        try rtf.write(to: rtfURL, options: .atomic)
        try pdfData(from: attributed).write(to: pdfURL, options: .atomic)
        try csvFromMarkdownTables(note.markdown).write(to: csvURL, atomically: true, encoding: .utf8)
        return [pdfURL, rtfURL, csvURL]
    }

    static func csvFromMarkdownTables(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        var tables: [[[String]]] = []
        var index = 0
        while index + 1 < lines.count {
            let header = tableCells(in: lines[index])
            let separator = tableCells(in: lines[index + 1])
            let isSeparator = !separator.isEmpty && separator.allSatisfy {
                $0.replacingOccurrences(of: ":", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .allSatisfy { $0 == "-" }
            }
            guard !header.isEmpty, header.count == separator.count, isSeparator else {
                index += 1
                continue
            }

            var rows = [header]
            index += 2
            while index < lines.count {
                let cells = tableCells(in: lines[index])
                guard !cells.isEmpty else { break }
                rows.append(cells)
                index += 1
            }
            tables.append(rows)
        }

        if tables.isEmpty {
            return "Note\n" + csvEscape(markdown.replacingOccurrences(of: "\n", with: " ")) + "\n"
        }
        return tables.enumerated().map { tableIndex, rows in
            let prefix = tables.count > 1 ? "Table \(tableIndex + 1)\n" : ""
            return prefix + rows.map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }

    private static func attributedDocument(for note: HubNote) -> NSAttributedString {
        let document = NSMutableAttributedString()
        #if os(macOS)
        let titleFont = NSFont.systemFont(ofSize: 26, weight: .bold)
        let bodyFont = NSFont.systemFont(ofSize: 14)
        let textColor = NSColor.labelColor
        #else
        let titleFont = UIFont.systemFont(ofSize: 26, weight: .bold)
        let bodyFont = UIFont.systemFont(ofSize: 14)
        let textColor = UIColor.label
        #endif
        document.append(NSAttributedString(
            string: note.title + "\n\n",
            attributes: [.font: titleFont, .foregroundColor: textColor]
        ))
        let body = (try? AttributedString(markdown: note.markdown))
            .map(NSAttributedString.init) ?? NSAttributedString(string: note.markdown)
        let mutableBody = NSMutableAttributedString(attributedString: body)
        if mutableBody.length > 0 {
            let bodyRange = NSRange(location: 0, length: mutableBody.length)
            mutableBody.addAttribute(.foregroundColor, value: textColor, range: bodyRange)
            mutableBody.enumerateAttribute(.font, in: bodyRange) { value, range, _ in
                if value == nil { mutableBody.addAttribute(.font, value: bodyFont, range: range) }
            }
        }
        document.append(mutableBody)
        return document
    }

    private static func pdfData(from attributed: NSAttributedString) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var location = 0
        repeat {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: mediaBox.height)
            context.scaleBy(x: 1, y: -1)
            let path = CGPath(rect: mediaBox.insetBy(dx: 54, dy: 54), transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: 0),
                path,
                nil
            )
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            location += visible.length
            context.restoreGState()
            context.endPDFPage()
            if visible.length == 0 { break }
        } while location < attributed.length
        context.closePDF()
        return data as Data
    }

    private static func tableCells(in line: String) -> [String] {
        guard line.contains("|") else { return [] }
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func safeFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return value.components(separatedBy: invalid).joined(separator: "-")
    }

    private static func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

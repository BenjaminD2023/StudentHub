import Foundation
import CoreGraphics
import CoreText
#if os(macOS)
import AppKit
private typealias HubNativeFont = NSFont
private typealias HubNativeColor = NSColor
#else
import UIKit
private typealias HubNativeFont = UIFont
private typealias HubNativeColor = UIColor
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

    static func exportedFiles() -> [URL] {
        try? prepareDirectories()
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: exportsURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter {
            (try? $0.resourceValues(forKeys: Set(keys)).isRegularFile) == true
        }.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
    }

    static func deleteExport(at url: URL) throws {
        let exportsPath = exportsURL.standardizedFileURL.path
        let candidate = url.standardizedFileURL
        guard candidate.deletingLastPathComponent().path == exportsPath else {
            throw CocoaError(.fileWriteNoPermission)
        }
        if FileManager.default.fileExists(atPath: candidate.path) {
            try FileManager.default.removeItem(at: candidate)
        }
    }

    static func deleteAllExports() throws {
        for url in exportedFiles() { try deleteExport(at: url) }
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
        let docxURL = exportsURL.appendingPathComponent(baseName).appendingPathExtension("docx")
        let rtfURL = exportsURL.appendingPathComponent(baseName).appendingPathExtension("rtf")
        let pdfURL = exportsURL.appendingPathComponent(baseName).appendingPathExtension("pdf")
        let csvURL = exportsURL.appendingPathComponent(baseName + "-tables").appendingPathExtension("csv")
        let attributed = attributedDocument(for: note)

        try officeOpenXMLData(for: note).write(to: docxURL, options: .atomic)
        let rtf = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        try rtf.write(to: rtfURL, options: .atomic)
        try pdfData(from: attributed).write(to: pdfURL, options: .atomic)
        try csvFromMarkdownTables(note.markdown).write(to: csvURL, atomically: true, encoding: .utf8)
        return [docxURL, pdfURL, rtfURL, csvURL]
    }

    static func officeOpenXMLData(for note: HubNote) throws -> Data {
        DOCXDocumentBuilder.data(for: note)
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
        let accent = nativeColor(hex: note.course.colorHex)
        let ink = nativeColor(hex: 0x20242B)
        let secondary = nativeColor(hex: 0x667085)
        let codeBackground = nativeColor(hex: 0xEEF2F7)
        document.append(NSAttributedString(
            string: note.title + "\n\n",
            attributes: [.font: nativeFont(size: 26, weight: .bold), .foregroundColor: accent]
        ))
        document.append(NSAttributedString(
            string: "\(note.course.title)  •  \(note.folder)\n\n",
            attributes: [.font: nativeFont(size: 10, weight: .semibold), .foregroundColor: secondary]
        ))

        var insideCodeBlock = false
        for line in note.markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                insideCodeBlock.toggle()
                continue
            }
            if insideCodeBlock {
                appendBlock(
                    line,
                    to: document,
                    size: 11,
                    weight: .regular,
                    color: ink,
                    monospaced: true,
                    background: codeBackground
                )
                continue
            }
            if trimmed.isEmpty {
                document.append(NSAttributedString(string: "\n"))
                continue
            }
            let headingLevel = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(headingLevel), trimmed.dropFirst(headingLevel).hasPrefix(" ") {
                let heading = String(trimmed.dropFirst(headingLevel + 1))
                let size: CGFloat = headingLevel == 1 ? 22 : (headingLevel == 2 ? 18 : 15)
                appendBlock(heading, to: document, size: size, weight: .bold, color: accent)
                continue
            }
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                let cells = tableCells(in: trimmed)
                let isDivider = !cells.isEmpty && cells.allSatisfy {
                    $0.replacingOccurrences(of: ":", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .allSatisfy { $0 == "-" }
                }
                if !isDivider {
                    appendBlock(
                        cells.joined(separator: "    "),
                        to: document,
                        size: 10.5,
                        weight: .medium,
                        color: ink,
                        monospaced: true,
                        background: codeBackground
                    )
                }
                continue
            }
            if trimmed.hasPrefix("> ") {
                appendBlock(
                    "▎ " + trimmed.dropFirst(2),
                    to: document,
                    size: 12,
                    weight: .regular,
                    color: secondary,
                    italic: true
                )
                continue
            }
            if trimmed == "---" {
                appendBlock("────────────────────────", to: document, size: 10, weight: .regular, color: accent)
                continue
            }
            let displayLine: String
            if trimmed.hasPrefix("- [ ] ") {
                displayLine = "☐ " + trimmed.dropFirst(6)
            } else if trimmed.lowercased().hasPrefix("- [x] ") {
                displayLine = "☑ " + trimmed.dropFirst(6)
            } else if trimmed.hasPrefix("- ") {
                displayLine = "• " + trimmed.dropFirst(2)
            } else {
                displayLine = line
            }
            appendBlock(displayLine, to: document, size: 12, weight: .regular, color: ink)
        }
        return document
    }

    private static func appendBlock(
        _ markdown: String,
        to document: NSMutableAttributedString,
        size: CGFloat,
        weight: HubNativeFont.Weight,
        color: HubNativeColor,
        italic: Bool = false,
        monospaced: Bool = false,
        background: HubNativeColor? = nil
    ) {
        let source = markdown as NSString
        let expression = try! NSRegularExpression(pattern: #"\{\{color:#([0-9A-Fa-f]{6})\|(.+?)\}\}"#)
        let matches = expression.matches(in: markdown, range: NSRange(location: 0, length: source.length))
        let block = NSMutableAttributedString()
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                block.append(styledInline(
                    source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
                    size: size,
                    weight: weight,
                    color: color,
                    italic: italic,
                    monospaced: monospaced,
                    background: background
                ))
            }
            let hex = UInt32(source.substring(with: match.range(at: 1)), radix: 16) ?? 0x20242B
            block.append(styledInline(
                source.substring(with: match.range(at: 2)),
                size: size,
                weight: weight,
                color: nativeColor(hex: hex),
                italic: italic,
                monospaced: monospaced,
                background: background
            ))
            cursor = NSMaxRange(match.range)
        }
        if cursor < source.length {
            block.append(styledInline(
                source.substring(from: cursor),
                size: size,
                weight: weight,
                color: color,
                italic: italic,
                monospaced: monospaced,
                background: background
            ))
        }
        block.append(NSAttributedString(string: "\n"))
        document.append(block)
    }

    private static func styledInline(
        _ markdown: String,
        size: CGFloat,
        weight: HubNativeFont.Weight,
        color: HubNativeColor,
        italic: Bool,
        monospaced: Bool,
        background: HubNativeColor?
    ) -> NSAttributedString {
        let parsed = (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )).map(NSAttributedString.init) ?? NSAttributedString(string: markdown)
        let block = NSMutableAttributedString(attributedString: parsed)
        let range = NSRange(location: 0, length: block.length)
        if range.length > 0 {
            block.addAttributes(
                [.font: nativeFont(size: size, weight: weight, italic: italic, monospaced: monospaced),
                 .foregroundColor: color],
                range: range
            )
            if let background { block.addAttribute(.backgroundColor, value: background, range: range) }

            let intentKey = NSAttributedString.Key("NSInlinePresentationIntent")
            block.enumerateAttribute(intentKey, in: range) { value, intentRange, _ in
                let intent = (value as? NSNumber)?.intValue ?? 0
                guard intent != 0 else { return }
                let isBold = intent & 2 != 0
                let isItalic = italic || intent & 1 != 0
                let isCode = monospaced || intent & 4 != 0
                block.addAttribute(
                    .font,
                    value: nativeFont(
                        size: isCode ? max(10, size - 0.5) : size,
                        weight: isBold ? .bold : weight,
                        italic: isItalic,
                        monospaced: isCode
                    ),
                    range: intentRange
                )
                if isCode { block.addAttribute(.backgroundColor, value: nativeColor(hex: 0xEEF2F7), range: intentRange) }
            }
            block.enumerateAttribute(.link, in: range) { value, linkRange, _ in
                if value != nil { block.addAttribute(.foregroundColor, value: nativeColor(hex: 0x2F6FED), range: linkRange) }
            }
        }
        return block
    }

    private static func nativeColor(hex: UInt32) -> HubNativeColor {
        HubNativeColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func nativeFont(
        size: CGFloat,
        weight: HubNativeFont.Weight,
        italic: Bool = false,
        monospaced: Bool = false
    ) -> HubNativeFont {
        let font = monospaced
            ? HubNativeFont.monospacedSystemFont(ofSize: size, weight: weight)
            : HubNativeFont.systemFont(ofSize: size, weight: weight)
        guard italic else { return font }
        #if os(macOS)
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        #else
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(.traitItalic) else { return font }
        return UIFont(descriptor: descriptor, size: size)
        #endif
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

private enum DOCXDocumentBuilder {
    private struct Entry {
        let name: String
        let data: Data
    }

    static func data(for note: HubNote) -> Data {
        archive([
            Entry(name: "[Content_Types].xml", data: Data(contentTypesXML.utf8)),
            Entry(name: "_rels/.rels", data: Data(packageRelationshipsXML.utf8)),
            Entry(name: "word/document.xml", data: Data(documentXML(for: note).utf8)),
            Entry(name: "word/styles.xml", data: Data(stylesXML.utf8)),
            Entry(name: "word/_rels/document.xml.rels", data: Data(documentRelationshipsXML.utf8))
        ])
    }

    private static func documentXML(for note: HubNote) -> String {
        let accent = String(format: "%06X", note.course.colorHex)
        var body = paragraphXML(note.title, size: 28, bold: true, color: accent, alignment: "center")
        body += paragraphXML(
            "\(note.course.title)  •  \(note.folder)",
            size: 10,
            bold: true,
            color: "667085",
            alignment: "center"
        )
        body += "<w:p/>"

        let lines = note.markdown.components(separatedBy: .newlines)
        var index = 0
        var insideCodeBlock = false
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                insideCodeBlock.toggle()
                index += 1
                continue
            }
            if insideCodeBlock {
                body += paragraphXML(line, size: 10, color: "344054", code: true, shading: "EEF2F7")
                index += 1
                continue
            }

            let header = tableCells(in: line)
            if !header.isEmpty, index + 1 < lines.count, isTableSeparator(lines[index + 1], columns: header.count) {
                var rows = [header]
                index += 2
                while index < lines.count {
                    let cells = tableCells(in: lines[index])
                    guard !cells.isEmpty else { break }
                    rows.append(cells)
                    index += 1
                }
                body += tableXML(rows, accent: accent)
                continue
            }

            if trimmed.isEmpty {
                body += "<w:p/>"
                index += 1
                continue
            }
            let headingLevel = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(headingLevel), trimmed.dropFirst(headingLevel).hasPrefix(" ") {
                let heading = String(trimmed.dropFirst(headingLevel + 1))
                let size = headingLevel == 1 ? 22 : (headingLevel == 2 ? 18 : 15)
                body += paragraphXML(heading, size: size, bold: true, color: accent, spacingBefore: 160)
            } else if trimmed.hasPrefix("> ") {
                body += paragraphXML(
                    "▎ " + String(trimmed.dropFirst(2)),
                    size: 11,
                    italic: true,
                    color: "667085",
                    leftIndent: 360
                )
            } else if trimmed == "---" {
                body += paragraphXML("────────────────────────", size: 9, color: accent)
            } else if trimmed.hasPrefix("- [ ] ") {
                body += paragraphXML("☐ " + String(trimmed.dropFirst(6)), size: 11, color: "20242B", leftIndent: 240)
            } else if trimmed.lowercased().hasPrefix("- [x] ") {
                body += paragraphXML("☑ " + String(trimmed.dropFirst(6)), size: 11, color: "667085", leftIndent: 240)
            } else if trimmed.hasPrefix("- ") {
                body += paragraphXML("• " + String(trimmed.dropFirst(2)), size: 11, color: "20242B", leftIndent: 240)
            } else {
                body += paragraphXML(line, size: 11, color: "20242B")
            }
            index += 1
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(body)
            <w:sectPr>
              <w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080" w:header="720" w:footer="720" w:gutter="0"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    private static func paragraphXML(
        _ markdown: String,
        size: Int,
        bold: Bool = false,
        italic: Bool = false,
        color: String,
        code: Bool = false,
        shading: String? = nil,
        alignment: String? = nil,
        leftIndent: Int? = nil,
        spacingBefore: Int = 0
    ) -> String {
        var properties = "<w:spacing w:before=\"\(spacingBefore)\" w:after=\"100\" w:line=\"300\" w:lineRule=\"auto\"/>"
        if let alignment { properties += "<w:jc w:val=\"\(alignment)\"/>" }
        if let leftIndent { properties += "<w:ind w:left=\"\(leftIndent)\"/>" }
        let runs = inlineRunsXML(
            markdown,
            size: size,
            baseBold: bold,
            baseItalic: italic,
            color: color,
            baseCode: code,
            shading: shading
        )
        return "<w:p><w:pPr>\(properties)</w:pPr>\(runs)</w:p>"
    }

    private static func inlineRunsXML(
        _ markdown: String,
        size: Int,
        baseBold: Bool,
        baseItalic: Bool,
        color: String,
        baseCode: Bool,
        shading: String?,
        baseUnderline: Bool = false,
        baseStrike: Bool = false
    ) -> String {
        let expression = try! NSRegularExpression(
            pattern: #"\{\{color:#([0-9A-Fa-f]{6})\|(.+?)\}\}|\{\{underline\|(.+?)\}\}|==(.+?)==|~~(.+?)~~|\*\*(.+?)\*\*|\*([^*\n]+?)\*|`([^`\n]+?)`|\[([^\]]+)\]\([^)]+\)"#
        )
        let source = markdown as NSString
        let matches = expression.matches(in: markdown, range: NSRange(location: 0, length: source.length))
        var output = ""
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                output += runXML(
                    source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)),
                    size: size,
                    bold: baseBold,
                    italic: baseItalic,
                    color: color,
                    code: baseCode,
                    shading: shading,
                    underline: baseUnderline,
                    strike: baseStrike
                )
            }
            if match.range(at: 1).location != NSNotFound {
                output += inlineRunsXML(
                    source.substring(with: match.range(at: 2)),
                    size: size,
                    baseBold: baseBold,
                    baseItalic: baseItalic,
                    color: source.substring(with: match.range(at: 1)).uppercased(),
                    baseCode: baseCode,
                    shading: shading,
                    baseUnderline: baseUnderline,
                    baseStrike: baseStrike
                )
            } else if match.range(at: 3).location != NSNotFound {
                output += inlineRunsXML(source.substring(with: match.range(at: 3)), size: size, baseBold: baseBold, baseItalic: baseItalic, color: color, baseCode: baseCode, shading: shading, baseUnderline: true, baseStrike: baseStrike)
            } else if match.range(at: 4).location != NSNotFound {
                output += inlineRunsXML(source.substring(with: match.range(at: 4)), size: size, baseBold: baseBold, baseItalic: baseItalic, color: color, baseCode: baseCode, shading: "FFF2A8", baseUnderline: baseUnderline, baseStrike: baseStrike)
            } else if match.range(at: 5).location != NSNotFound {
                output += inlineRunsXML(source.substring(with: match.range(at: 5)), size: size, baseBold: baseBold, baseItalic: baseItalic, color: color, baseCode: baseCode, shading: shading, baseUnderline: baseUnderline, baseStrike: true)
            } else if match.range(at: 6).location != NSNotFound {
                output += inlineRunsXML(source.substring(with: match.range(at: 6)), size: size, baseBold: true, baseItalic: baseItalic, color: color, baseCode: baseCode, shading: shading, baseUnderline: baseUnderline, baseStrike: baseStrike)
            } else if match.range(at: 7).location != NSNotFound {
                output += inlineRunsXML(source.substring(with: match.range(at: 7)), size: size, baseBold: baseBold, baseItalic: true, color: color, baseCode: baseCode, shading: shading, baseUnderline: baseUnderline, baseStrike: baseStrike)
            } else if match.range(at: 8).location != NSNotFound {
                output += runXML(source.substring(with: match.range(at: 8)), size: max(9, size - 1), bold: baseBold, italic: baseItalic, color: "344054", code: true, shading: "EEF2F7", underline: baseUnderline, strike: baseStrike)
            } else {
                output += runXML(source.substring(with: match.range(at: 9)), size: size, bold: baseBold, italic: baseItalic, color: "2F6FED", code: false, shading: nil, underline: true, strike: baseStrike)
            }
            cursor = NSMaxRange(match.range)
        }
        if cursor < source.length {
            output += runXML(
                source.substring(from: cursor),
                size: size,
                bold: baseBold,
                italic: baseItalic,
                color: color,
                code: baseCode,
                shading: shading,
                underline: baseUnderline,
                strike: baseStrike
            )
        }
        return output
    }

    private static func runXML(
        _ text: String,
        size: Int,
        bold: Bool,
        italic: Bool,
        color: String,
        code: Bool,
        shading: String?,
        underline: Bool = false,
        strike: Bool = false
    ) -> String {
        guard !text.isEmpty else { return "" }
        var properties = "<w:color w:val=\"\(color)\"/><w:sz w:val=\"\(size * 2)\"/><w:szCs w:val=\"\(size * 2)\"/>"
        if bold { properties += "<w:b/><w:bCs/>" }
        if italic { properties += "<w:i/><w:iCs/>" }
        if underline { properties += "<w:u w:val=\"single\"/>" }
        if strike { properties += "<w:strike/>" }
        if code { properties += "<w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Menlo\"/>" }
        if let shading { properties += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(shading)\"/>" }
        return "<w:r><w:rPr>\(properties)</w:rPr><w:t xml:space=\"preserve\">\(xmlEscape(text))</w:t></w:r>"
    }

    private static func tableXML(_ rows: [[String]], accent: String) -> String {
        guard let columnCount = rows.map(\.count).max(), columnCount > 0 else { return "" }
        let grid = String(repeating: "<w:gridCol w:w=\"2400\"/>", count: columnCount)
        let body = rows.enumerated().map { rowIndex, row in
            let cells = (0..<columnCount).map { columnIndex -> String in
                let value = columnIndex < row.count ? row[columnIndex] : ""
                let fill = rowIndex == 0 ? "E8EEF9" : (rowIndex.isMultiple(of: 2) ? "F8FAFC" : "FFFFFF")
                let runs = inlineRunsXML(value, size: 10, baseBold: rowIndex == 0, baseItalic: false, color: rowIndex == 0 ? accent : "20242B", baseCode: false, shading: nil)
                return "<w:tc><w:tcPr><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(fill)\"/><w:tcMar><w:top w:w=\"80\" w:type=\"dxa\"/><w:left w:w=\"100\" w:type=\"dxa\"/><w:bottom w:w=\"80\" w:type=\"dxa\"/><w:right w:w=\"100\" w:type=\"dxa\"/></w:tcMar></w:tcPr><w:p>\(runs)</w:p></w:tc>"
            }.joined()
            return "<w:tr>\(cells)</w:tr>"
        }.joined()
        return """
        <w:tbl>
          <w:tblPr><w:tblW w:w="0" w:type="auto"/><w:tblBorders><w:top w:val="single" w:sz="4" w:color="D0D5DD"/><w:left w:val="single" w:sz="4" w:color="D0D5DD"/><w:bottom w:val="single" w:sz="4" w:color="D0D5DD"/><w:right w:val="single" w:sz="4" w:color="D0D5DD"/><w:insideH w:val="single" w:sz="4" w:color="D0D5DD"/><w:insideV w:val="single" w:sz="4" w:color="D0D5DD"/></w:tblBorders></w:tblPr>
          <w:tblGrid>\(grid)</w:tblGrid>
          \(body)
        </w:tbl>
        """
    }

    private static func tableCells(in line: String) -> [String] {
        guard line.contains("|") else { return [] }
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ line: String, columns: Int) -> Bool {
        let cells = tableCells(in: line)
        return cells.count == columns && cells.allSatisfy {
            let dashes = $0.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
            return dashes.count >= 3 && dashes.allSatisfy { $0 == "-" }
        }
    }

    private static func xmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func archive(_ entries: [Entry]) -> Data {
        var output = Data()
        var centralDirectory = Data()

        for entry in entries {
            let fileName = Data(entry.name.utf8)
            let checksum = crc32(entry.data)
            let offset = UInt32(output.count)

            append(UInt32(0x04034B50), to: &output)
            append(UInt16(20), to: &output)
            append(UInt16(0), to: &output)
            append(UInt16(0), to: &output)
            append(UInt16(0), to: &output)
            append(UInt16(0), to: &output)
            append(checksum, to: &output)
            append(UInt32(entry.data.count), to: &output)
            append(UInt32(entry.data.count), to: &output)
            append(UInt16(fileName.count), to: &output)
            append(UInt16(0), to: &output)
            output.append(fileName)
            output.append(entry.data)

            append(UInt32(0x02014B50), to: &centralDirectory)
            append(UInt16(20), to: &centralDirectory)
            append(UInt16(20), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(checksum, to: &centralDirectory)
            append(UInt32(entry.data.count), to: &centralDirectory)
            append(UInt32(entry.data.count), to: &centralDirectory)
            append(UInt16(fileName.count), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(UInt16(0), to: &centralDirectory)
            append(UInt32(0), to: &centralDirectory)
            append(offset, to: &centralDirectory)
            centralDirectory.append(fileName)
        }

        let centralOffset = UInt32(output.count)
        output.append(centralDirectory)
        append(UInt32(0x06054B50), to: &output)
        append(UInt16(0), to: &output)
        append(UInt16(0), to: &output)
        append(UInt16(entries.count), to: &output)
        append(UInt16(entries.count), to: &output)
        append(UInt32(centralDirectory.count), to: &output)
        append(centralOffset, to: &output)
        append(UInt16(0), to: &output)
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var value = UInt32.max
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 {
                value = value & 1 == 1 ? (value >> 1) ^ 0xEDB88320 : value >> 1
            }
        }
        return value ^ UInt32.max
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
    </Types>
    """

    private static let packageRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    private static let documentRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
      <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
        <w:name w:val="Normal"/><w:qFormat/>
        <w:rPr><w:rFonts w:ascii="Aptos" w:hAnsi="Aptos"/><w:color w:val="20242B"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr>
      </w:style>
    </w:styles>
    """
}

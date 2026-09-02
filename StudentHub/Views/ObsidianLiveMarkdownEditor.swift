import SwiftUI

#if os(macOS)
import AppKit
import CoreText
#else
import UIKit
#endif

/// A single-canvas Markdown editor. On macOS, Markdown syntax is visible only
/// for the paragraph that currently owns the cursor; every other paragraph is
/// styled in place so reading and editing happen in the same surface.
struct ObsidianLiveMarkdownEditor: View {
    @Binding var text: String
    var targetLine: Int?
    var selection: Binding<NSRange>? = nil
    var onSelectionChange: (NSRange) -> Void = { _ in }

    var body: some View {
        #if os(macOS)
        MacLiveMarkdownTextView(text: $text, targetLine: targetLine, selection: selection, onSelectionChange: onSelectionChange)
        #else
        IPhoneLiveMarkdownTextView(text: $text, targetLine: targetLine, selection: selection, onSelectionChange: onSelectionChange)
        #endif
    }
}

#if os(iOS)
private final class MarkdownUITextView: UITextView {
    var onMarkdownShortcut: ((MarkdownTool) -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(title: "Bold", action: #selector(applyBold), input: "b", modifierFlags: .command),
            UIKeyCommand(title: "Italic", action: #selector(applyItalic), input: "i", modifierFlags: .command),
            UIKeyCommand(title: "Underline", action: #selector(applyUnderline), input: "u", modifierFlags: .command),
            UIKeyCommand(title: "Add Link", action: #selector(applyLink), input: "k", modifierFlags: .command)
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands + (super.keyCommands ?? [])
    }

    @objc private func applyBold() { onMarkdownShortcut?(.bold) }
    @objc private func applyItalic() { onMarkdownShortcut?(.italic) }
    @objc private func applyUnderline() { onMarkdownShortcut?(.underline) }
    @objc private func applyLink() { onMarkdownShortcut?(.link) }
}

private struct IPhoneLiveMarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    let targetLine: Int?
    let selection: Binding<NSRange>?
    let onSelectionChange: (NSRange) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = MarkdownUITextView()
        textView.delegate = context.coordinator
        textView.onMarkdownShortcut = { [weak coordinator = context.coordinator, weak textView] tool in
            guard let textView else { return }
            coordinator?.apply(tool, to: textView)
        }
        textView.text = text
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 18, right: 10)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.accessibilityLabel = "Markdown live preview editor"
        let checkboxTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCheckboxTap(_:))
        )
        checkboxTap.delegate = context.coordinator
        checkboxTap.cancelsTouchesInView = true
        textView.addGestureRecognizer(checkboxTap)
        context.coordinator.render(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if textView.text != text {
            let selection = textView.selectedRange
            context.coordinator.isApplyingExternalUpdate = true
            textView.text = text
            let requested = self.selection?.wrappedValue ?? selection
            textView.selectedRange = NSRange(
                location: min(requested.location, (text as NSString).length),
                length: min(requested.length, max(0, (text as NSString).length - min(requested.location, (text as NSString).length)))
            )
            context.coordinator.isApplyingExternalUpdate = false
        }
        context.coordinator.render(textView)
        context.coordinator.scrollIfNeeded(textView, targetLine: targetLine)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: IPhoneLiveMarkdownTextView
        var isApplyingExternalUpdate = false
        private var lastTargetLine: Int?

        init(parent: IPhoneLiveMarkdownTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingExternalUpdate else { return }
            parent.text = textView.text
            render(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selection?.wrappedValue = textView.selectedRange
            parent.onSelectionChange(textView.selectedRange)
            render(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            render(textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            render(textView)
        }

        func apply(_ tool: MarkdownTool, to textView: UITextView) {
            let result = tool.applyingShortcut(to: textView.text, selection: textView.selectedRange)
            isApplyingExternalUpdate = true
            textView.text = result.text
            textView.selectedRange = result.selection
            isApplyingExternalUpdate = false
            parent.text = result.text
            parent.selection?.wrappedValue = result.selection
            parent.onSelectionChange(result.selection)
            render(textView)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let textView = gestureRecognizer.view as? UITextView,
                  let index = characterIndex(for: gestureRecognizer, in: textView) else { return false }
            return MarkdownChecklist.togglingMarker(in: textView.text, characterIndex: index) != nil
        }

        @objc func handleCheckboxTap(_ gestureRecognizer: UITapGestureRecognizer) {
            guard gestureRecognizer.state == .ended,
                  let textView = gestureRecognizer.view as? UITextView,
                  let index = characterIndex(for: gestureRecognizer, in: textView),
                  let result = MarkdownChecklist.togglingMarker(
                    in: textView.text,
                    characterIndex: index
                  ) else { return }
            isApplyingExternalUpdate = true
            textView.text = result.text
            textView.selectedRange = result.selection
            isApplyingExternalUpdate = false
            parent.text = result.text
            parent.selection?.wrappedValue = result.selection
            parent.onSelectionChange(result.selection)
            render(textView)
        }

        private func characterIndex(for gestureRecognizer: UIGestureRecognizer, in textView: UITextView) -> Int? {
            let point = gestureRecognizer.location(in: textView)
            guard let position = textView.closestPosition(to: point) else { return nil }
            return textView.offset(from: textView.beginningOfDocument, to: position)
        }

        func render(_ textView: UITextView) {
            let storage = textView.textStorage
            let source = textView.text as NSString
            let fullRange = NSRange(location: 0, length: source.length)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacing = 7

            storage.beginEditing()
            if fullRange.length > 0 {
                storage.setAttributes(
                    [
                        .font: UIFont.systemFont(ofSize: 16),
                        .foregroundColor: UIColor.label,
                        .paragraphStyle: paragraph
                    ],
                    range: fullRange
                )
            }

            let activeRange = textView.isFirstResponder
                ? source.lineRange(for: NSRange(location: min(textView.selectedRange.location, source.length), length: 0))
                : nil
            var cursor = 0
            var isInsideCodeBlock = false
            while cursor < source.length {
                var start = 0
                var end = 0
                var contentsEnd = 0
                source.getLineStart(
                    &start,
                    end: &end,
                    contentsEnd: &contentsEnd,
                    for: NSRange(location: cursor, length: 0)
                )
                let lineRange = NSRange(location: start, length: contentsEnd - start)
                if let activeRange,
                   NSIntersectionRange(activeRange, lineRange).length > 0 ||
                    (lineRange.length == 0 && activeRange.location == lineRange.location) {
                    styleEditingLine(storage, source: source, range: lineRange)
                } else {
                    styleRenderedLine(
                        storage,
                        source: source,
                        range: lineRange,
                        isInsideCodeBlock: &isInsideCodeBlock
                    )
                }
                cursor = max(end, cursor + 1)
            }
            storage.endEditing()
            textView.typingAttributes = [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph
            ]
        }

        func scrollIfNeeded(_ textView: UITextView, targetLine: Int?) {
            guard targetLine != lastTargetLine else { return }
            lastTargetLine = targetLine
            guard let targetLine else { return }

            let source = textView.text as NSString
            var cursor = 0
            var line = 0
            while cursor < source.length {
                var start = 0
                var end = 0
                var contentsEnd = 0
                source.getLineStart(
                    &start,
                    end: &end,
                    contentsEnd: &contentsEnd,
                    for: NSRange(location: cursor, length: 0)
                )
                if line == targetLine {
                    textView.selectedRange = NSRange(location: start, length: 0)
                    textView.scrollRangeToVisible(NSRange(location: start, length: max(contentsEnd - start, 0)))
                    return
                }
                line += 1
                cursor = max(end, cursor + 1)
            }
        }

        private func styleRenderedLine(
            _ storage: NSTextStorage,
            source: NSString,
            range: NSRange,
            isInsideCodeBlock: inout Bool
        ) {
            guard range.length > 0 else { return }
            let line = source.substring(with: range)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                hide(storage, range: range)
                isInsideCodeBlock.toggle()
                return
            }
            if isInsideCodeBlock {
                storage.addAttributes(
                    [
                        .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                        .backgroundColor: UIColor.secondarySystemFill
                    ],
                    range: range
                )
                return
            }

            if trimmed.hasPrefix("|"), trimmed.hasSuffix("|") {
                let isDivider = trimmed
                    .replacingOccurrences(of: "|", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .isEmpty
                if isDivider {
                    hide(storage, range: range)
                } else {
                    storage.addAttributes(
                        [
                            .font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular),
                            .backgroundColor: UIColor.secondarySystemFill
                        ],
                        range: range
                    )
                    applyColorStyles(storage, line: line, lineRange: range)
                }
                return
            }

            if let heading = firstMatch(#"^(#{1,6})\s+(.*)$"#, in: line) {
                let marker = globalRange(heading.range(at: 1), lineRange: range)
                let title = globalRange(heading.range(at: 2), lineRange: range)
                hide(storage, range: NSRange(location: marker.location, length: marker.length + 1))
                let level = heading.range(at: 1).length
                let size: CGFloat = switch level {
                case 1: 27
                case 2: 22
                case 3: 19
                default: 16
                }
                storage.addAttribute(
                    .font,
                    value: UIFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold),
                    range: title
                )
                applyColorStyles(storage, line: line, lineRange: range)
                return
            }

            if let checklist = firstMatch(#"^(\s*[-*+]\s+\[[ xX]\]\s+)(.*)$"#, in: line) {
                applyChecklistStyle(storage, line: line, lineRange: range, match: checklist)
            } else if let bullet = firstMatch(#"^(\s*[-*+]\s+)(.*)$"#, in: line) {
                storage.addAttribute(
                    .foregroundColor,
                    value: UIColor.systemBlue,
                    range: globalRange(bullet.range(at: 1), lineRange: range)
                )
            } else if let quote = firstMatch(#"^(\s*>\s+)(.*)$"#, in: line) {
                storage.addAttribute(
                    .foregroundColor,
                    value: UIColor.systemBlue,
                    range: globalRange(quote.range(at: 1), lineRange: range)
                )
                storage.addAttributes(
                    [.foregroundColor: UIColor.secondaryLabel, .font: UIFont.italicSystemFont(ofSize: 16)],
                    range: globalRange(quote.range(at: 2), lineRange: range)
                )
            }

            applyInlineStyles(storage, line: line, lineRange: range)
        }

        private func styleEditingLine(_ storage: NSTextStorage, source: NSString, range: NSRange) {
            guard range.length > 0 else { return }
            let line = source.substring(with: range)
            storage.addAttributes(
                [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.label],
                range: range
            )
            if let heading = firstMatch(#"^(#{1,6})\s+(.*)$"#, in: line) {
                let marker = globalRange(heading.range(at: 1), lineRange: range)
                let title = globalRange(heading.range(at: 2), lineRange: range)
                let level = heading.range(at: 1).length
                let size: CGFloat = switch level {
                case 1: 27
                case 2: 22
                case 3: 19
                default: 16
                }
                storage.addAttributes(
                    [.font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: UIColor.secondaryLabel],
                    range: marker
                )
                storage.addAttribute(
                    .font,
                    value: UIFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold),
                    range: title
                )
            }
            if let checklist = firstMatch(#"^(\s*[-*+]\s+\[[ xX]\]\s+)(.*)$"#, in: line) {
                applyChecklistStyle(storage, line: line, lineRange: range, match: checklist)
            }
            applyVisibleInlineStyles(storage, line: line, lineRange: range)
        }

        private func applyVisibleInlineStyles(_ storage: NSTextStorage, line: String, lineRange: NSRange) {
            applyColorStyles(storage, line: line, lineRange: lineRange)
            for match in matches(#"\*\*(.+?)\*\*"#, in: line) {
                storage.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 16), range: globalRange(match.range(at: 1), lineRange: lineRange))
            }
            for match in matches(#"(?<!\*)\*([^*\n]+)\*(?!\*)"#, in: line) {
                storage.addAttribute(.font, value: UIFont.italicSystemFont(ofSize: 16), range: globalRange(match.range(at: 1), lineRange: lineRange))
            }
            for match in matches(#"`([^`\n]+)`"#, in: line) {
                storage.addAttributes(
                    [.font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular), .backgroundColor: UIColor.secondarySystemFill],
                    range: globalRange(match.range(at: 1), lineRange: lineRange)
                )
            }
            for match in matches(#"~~(.+?)~~"#, in: line) {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: globalRange(match.range(at: 1), lineRange: lineRange))
            }
            for match in matches(#"==(.+?)=="#, in: line) {
                storage.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.42), range: globalRange(match.range(at: 1), lineRange: lineRange))
            }
            for match in matches(#"\{\{underline\|(.+?)\}\}"#, in: line) {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: globalRange(match.range(at: 1), lineRange: lineRange))
            }
        }

        private func applyInlineStyles(_ storage: NSTextStorage, line: String, lineRange: NSRange) {
            applyColorStyles(storage, line: line, lineRange: lineRange)
            for match in matches(#"\*\*(.+?)\*\*"#, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let content = globalRange(match.range(at: 1), lineRange: lineRange)
                hide(storage, range: NSRange(location: full.location, length: 2))
                hide(storage, range: NSRange(location: NSMaxRange(full) - 2, length: 2))
                storage.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 16), range: content)
            }
            for match in matches(#"(?<!\*)\*([^*\n]+)\*(?!\*)"#, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let content = globalRange(match.range(at: 1), lineRange: lineRange)
                hide(storage, range: NSRange(location: full.location, length: 1))
                hide(storage, range: NSRange(location: NSMaxRange(full) - 1, length: 1))
                storage.addAttribute(.font, value: UIFont.italicSystemFont(ofSize: 16), range: content)
            }
            for match in matches(#"`([^`\n]+)`"#, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let content = globalRange(match.range(at: 1), lineRange: lineRange)
                hide(storage, range: NSRange(location: full.location, length: 1))
                hide(storage, range: NSRange(location: NSMaxRange(full) - 1, length: 1))
                storage.addAttributes(
                    [.font: UIFont.monospacedSystemFont(ofSize: 14, weight: .regular), .backgroundColor: UIColor.secondarySystemFill],
                    range: content
                )
            }
            for match in matches(#"~~(.+?)~~"#, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let content = globalRange(match.range(at: 1), lineRange: lineRange)
                hide(storage, range: NSRange(location: full.location, length: 2))
                hide(storage, range: NSRange(location: NSMaxRange(full) - 2, length: 2))
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
            }
            for match in matches(#"==(.+?)=="#, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let content = globalRange(match.range(at: 1), lineRange: lineRange)
                hide(storage, range: NSRange(location: full.location, length: 2))
                hide(storage, range: NSRange(location: NSMaxRange(full) - 2, length: 2))
                storage.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.42), range: content)
            }
            for match in matches(#"\{\{underline\|(.+?)\}\}"#, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let content = globalRange(match.range(at: 1), lineRange: lineRange)
                hide(storage, range: NSRange(location: full.location, length: content.location - full.location))
                hide(storage, range: NSRange(location: NSMaxRange(content), length: NSMaxRange(full) - NSMaxRange(content)))
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: content)
            }
            for match in matches(#"\[([^\]]+)\]\(([^)]+)\)"#, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let label = globalRange(match.range(at: 1), lineRange: lineRange)
                hide(storage, range: NSRange(location: full.location, length: label.location - full.location))
                hide(storage, range: NSRange(location: NSMaxRange(label), length: NSMaxRange(full) - NSMaxRange(label)))
                storage.addAttributes(
                    [.foregroundColor: UIColor.link, .underlineStyle: NSUnderlineStyle.single.rawValue],
                    range: label
                )
            }
        }

        private func applyChecklistStyle(
            _ storage: NSTextStorage,
            line: String,
            lineRange: NSRange,
            match: NSTextCheckingResult
        ) {
            let marker = globalRange(match.range(at: 1), lineRange: lineRange)
            let item = globalRange(match.range(at: 2), lineRange: lineRange)
            let isChecked = line.range(of: "[x]", options: .caseInsensitive) != nil
            hide(storage, range: marker)
            let attachment = NSTextAttachment()
            attachment.image = UIImage(systemName: isChecked ? "checkmark.square.fill" : "square")
            attachment.bounds = CGRect(x: 0, y: -3, width: 17, height: 17)
            storage.addAttributes(
                [
                    .attachment: attachment,
                    .font: UIFont.systemFont(ofSize: 16),
                    .foregroundColor: UIColor.systemBlue
                ],
                range: NSRange(location: marker.location, length: 1)
            )
            if isChecked {
                storage.addAttributes(
                    [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: UIColor.secondaryLabel],
                    range: item
                )
            }
        }

        private func applyColorStyles(_ storage: NSTextStorage, line: String, lineRange: NSRange) {
            for match in matches(MarkdownColorFormatting.pattern, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let content = globalRange(match.range(at: 2), lineRange: lineRange)
                let hex = (line as NSString).substring(with: match.range(at: 1))
                hide(storage, range: NSRange(location: full.location, length: content.location - full.location))
                hide(storage, range: NSRange(location: NSMaxRange(content), length: NSMaxRange(full) - NSMaxRange(content)))
                storage.addAttribute(.foregroundColor, value: uiColor(hex), range: content)
            }
        }

        private func uiColor(_ hex: String) -> UIColor {
            let value = UInt32(hex, radix: 16) ?? 0x20242B
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }

        private func hide(_ storage: NSTextStorage, range: NSRange) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            storage.addAttributes(
                [.foregroundColor: UIColor.clear, .font: UIFont.systemFont(ofSize: 0.1)],
                range: range
            )
        }

        private func firstMatch(_ pattern: String, in string: String) -> NSTextCheckingResult? {
            matches(pattern, in: string).first
        }

        private func matches(_ pattern: String, in string: String) -> [NSTextCheckingResult] {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
            return expression.matches(
                in: string,
                range: NSRange(location: 0, length: (string as NSString).length)
            )
        }

        private func globalRange(_ localRange: NSRange, lineRange: NSRange) -> NSRange {
            guard localRange.location != NSNotFound else { return localRange }
            return NSRange(location: lineRange.location + localRange.location, length: localRange.length)
        }
    }
}
#endif

#if os(macOS)
private final class MarkdownNSTextView: NSTextView {
    var onMarkdownShortcut: ((MarkdownTool) -> Void)?
    var onChecklistClick: ((Int) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": onMarkdownShortcut?(.bold)
        case "i": onMarkdownShortcut?(.italic)
        case "u": onMarkdownShortcut?(.underline)
        case "k": onMarkdownShortcut?(.link)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let layoutManager,
           let textContainer,
           point.x >= textContainerOrigin.x,
           point.y >= textContainerOrigin.y {
            let containerPoint = NSPoint(
                x: point.x - textContainerOrigin.x,
                y: point.y - textContainerOrigin.y
            )
            let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            if onChecklistClick?(characterIndex) == true { return }
        }
        super.mouseDown(with: event)
    }
}

private struct MacLiveMarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    let targetLine: Int?
    let selection: Binding<NSRange>?
    let onSelectionChange: (NSRange) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = MarkdownNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.onMarkdownShortcut = { [weak coordinator = context.coordinator, weak textView] tool in
            guard let textView else { return }
            coordinator?.apply(tool, to: textView)
        }
        textView.onChecklistClick = { [weak coordinator = context.coordinator, weak textView] index in
            guard let textView else { return false }
            return coordinator?.toggleChecklist(at: index, in: textView) ?? false
        }
        textView.string = text
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 30, height: 26)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.setAccessibilityLabel("Markdown live preview editor")
        scrollView.documentView = textView

        context.coordinator.render(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self

        if textView.string != text {
            let selection = textView.selectedRange()
            context.coordinator.isApplyingExternalUpdate = true
            textView.string = text
            let requested = self.selection?.wrappedValue ?? selection
            let location = min(requested.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(
                location: location,
                length: min(requested.length, max(0, (text as NSString).length - location))
            ))
            context.coordinator.isApplyingExternalUpdate = false
        }

        context.coordinator.render(textView)
        context.coordinator.scrollIfNeeded(textView, targetLine: targetLine)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacLiveMarkdownTextView
        var isApplyingExternalUpdate = false
        private var isEditing = false
        private var lastTargetLine: Int?

        init(parent: MacLiveMarkdownTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
            guard let textView = notification.object as? NSTextView else { return }
            render(textView)
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            guard let textView = notification.object as? NSTextView else { return }
            render(textView)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalUpdate,
                  let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            render(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.selection?.wrappedValue = textView.selectedRange()
            parent.onSelectionChange(textView.selectedRange())
            render(textView)
        }

        func apply(_ tool: MarkdownTool, to textView: NSTextView) {
            let result = tool.applyingShortcut(to: textView.string, selection: textView.selectedRange())
            isApplyingExternalUpdate = true
            textView.string = result.text
            textView.setSelectedRange(result.selection)
            isApplyingExternalUpdate = false
            parent.text = result.text
            parent.selection?.wrappedValue = result.selection
            parent.onSelectionChange(result.selection)
            render(textView)
        }

        func toggleChecklist(at characterIndex: Int, in textView: NSTextView) -> Bool {
            guard let result = MarkdownChecklist.togglingMarker(
                in: textView.string,
                characterIndex: characterIndex
            ) else { return false }
            isApplyingExternalUpdate = true
            textView.string = result.text
            textView.setSelectedRange(result.selection)
            isApplyingExternalUpdate = false
            parent.text = result.text
            parent.selection?.wrappedValue = result.selection
            parent.onSelectionChange(result.selection)
            render(textView)
            return true
        }

        func render(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let source = textView.string as NSString
            let fullRange = NSRange(location: 0, length: source.length)
            let bodyFont = NSFont.systemFont(ofSize: 15)
            let bodyParagraph = NSMutableParagraphStyle()
            bodyParagraph.lineSpacing = 4
            bodyParagraph.paragraphSpacing = 7

            storage.beginEditing()
            if fullRange.length > 0 {
                storage.setAttributes(
                    [
                        .font: bodyFont,
                        .foregroundColor: NSColor.labelColor,
                        .paragraphStyle: bodyParagraph
                    ],
                    range: fullRange
                )
            }

            let ownsKeyboardFocus = textView.window?.firstResponder === textView
            let activeRange = isEditing || ownsKeyboardFocus
                ? activeLineRange(in: source, selection: textView.selectedRange())
                : nil
            var cursor = 0
            var isInsideCodeBlock = false

            while cursor < source.length {
                var lineStart = 0
                var lineEnd = 0
                var contentsEnd = 0
                source.getLineStart(
                    &lineStart,
                    end: &lineEnd,
                    contentsEnd: &contentsEnd,
                    for: NSRange(location: cursor, length: 0)
                )
                let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)

                if let activeRange, NSIntersectionRange(activeRange, lineRange).length > 0 ||
                    (lineRange.length == 0 && activeRange.location == lineRange.location) {
                    styleEditingLine(storage, source: source, range: lineRange)
                } else {
                    styleRenderedLine(
                        storage,
                        source: source,
                        range: lineRange,
                        isInsideCodeBlock: &isInsideCodeBlock
                    )
                }

                cursor = max(lineEnd, cursor + 1)
            }
            storage.endEditing()

            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: bodyParagraph
            ]
        }

        func scrollIfNeeded(_ textView: NSTextView, targetLine: Int?) {
            guard targetLine != lastTargetLine else { return }
            lastTargetLine = targetLine
            guard let targetLine else { return }

            let source = textView.string as NSString
            var cursor = 0
            var currentLine = 0
            while cursor < source.length {
                var start = 0
                var end = 0
                var contentsEnd = 0
                source.getLineStart(
                    &start,
                    end: &end,
                    contentsEnd: &contentsEnd,
                    for: NSRange(location: cursor, length: 0)
                )
                if currentLine == targetLine {
                    textView.setSelectedRange(NSRange(location: start, length: 0))
                    textView.scrollRangeToVisible(NSRange(location: start, length: max(contentsEnd - start, 0)))
                    render(textView)
                    return
                }
                currentLine += 1
                cursor = max(end, cursor + 1)
            }
        }

        private func activeLineRange(in source: NSString, selection: NSRange) -> NSRange {
            source.lineRange(
                for: NSRange(location: min(selection.location, source.length), length: 0)
            )
        }

        private func styleEditingLine(_ storage: NSTextStorage, source: NSString, range: NSRange) {
            guard range.length > 0 else { return }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacing = 7
            storage.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: 15),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph
                ],
                range: range
            )
            let line = source.substring(with: range)
            if let heading = firstMatch(#"^(#{1,6})\s+(.*)$"#, in: line) {
                let marker = globalRange(heading.range(at: 1), lineRange: range)
                let title = globalRange(heading.range(at: 2), lineRange: range)
                let level = heading.range(at: 1).length
                let size: CGFloat = switch level {
                case 1: 27
                case 2: 22
                case 3: 18
                default: 15
                }
                storage.addAttributes(
                    [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor],
                    range: marker
                )
                storage.addAttribute(
                    .font,
                    value: NSFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold),
                    range: title
                )
            }
            if let checklist = firstMatch(#"^(\s*[-*+]\s+\[[ xX]\]\s+)(.*)$"#, in: line) {
                applyChecklistStyle(storage, line: line, lineRange: range, match: checklist)
            }
            applyVisibleInlineStyles(storage, line: line, lineRange: range)
        }

        private func applyVisibleInlineStyles(
            _ storage: NSTextStorage,
            line: String,
            lineRange: NSRange
        ) {
            applyColorStyles(storage, line: line, lineRange: lineRange)
            for match in matches(#"\*\*(.+?)\*\*"#, in: line) {
                storage.addAttribute(
                    .font,
                    value: NSFont.systemFont(ofSize: 15, weight: .bold),
                    range: globalRange(match.range(at: 1), lineRange: lineRange)
                )
            }
            for match in matches(#"(?<!\*)\*([^*\n]+)\*(?!\*)"#, in: line) {
                storage.addAttribute(
                    .font,
                    value: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 15), toHaveTrait: .italicFontMask),
                    range: globalRange(match.range(at: 1), lineRange: lineRange)
                )
            }
            for match in matches(#"`([^`\n]+)`"#, in: line) {
                storage.addAttributes(
                    [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.18)],
                    range: globalRange(match.range(at: 1), lineRange: lineRange)
                )
            }
            for match in matches(#"~~(.+?)~~"#, in: line) {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: globalRange(match.range(at: 1), lineRange: lineRange))
            }
            for match in matches(#"==(.+?)=="#, in: line) {
                storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.42), range: globalRange(match.range(at: 1), lineRange: lineRange))
            }
            for match in matches(#"\{\{underline\|(.+?)\}\}"#, in: line) {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: globalRange(match.range(at: 1), lineRange: lineRange))
            }
        }

        private func styleRenderedLine(
            _ storage: NSTextStorage,
            source: NSString,
            range: NSRange,
            isInsideCodeBlock: inout Bool
        ) {
            guard range.length > 0 else { return }
            let line = source.substring(with: range)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                hide(storage, range: range)
                isInsideCodeBlock.toggle()
                return
            }

            if isInsideCodeBlock {
                storage.addAttributes(
                    [
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                        .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12)
                    ],
                    range: range
                )
                return
            }

            if trimmed.hasPrefix("|"), trimmed.hasSuffix("|") {
                let isDivider = trimmed
                    .replacingOccurrences(of: "|", with: "")
                    .replacingOccurrences(of: ":", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .isEmpty
                if isDivider {
                    hide(storage, range: range)
                } else {
                    storage.addAttributes(
                        [
                            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                            .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12)
                        ],
                        range: range
                    )
                    applyColorStyles(storage, line: line, lineRange: range)
                }
                return
            }

            if let heading = firstMatch(#"^(#{1,6})\s+(.*)$"#, in: line) {
                let marker = globalRange(heading.range(at: 1), lineRange: range)
                let title = globalRange(heading.range(at: 2), lineRange: range)
                hide(storage, range: NSRange(location: marker.location, length: marker.length + 1))
                let level = heading.range(at: 1).length
                let size: CGFloat = switch level {
                case 1: 27
                case 2: 22
                case 3: 18
                default: 15
                }
                storage.addAttributes(
                    [
                        .font: NSFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold),
                        .foregroundColor: NSColor.labelColor
                    ],
                    range: title
                )
                applyColorStyles(storage, line: line, lineRange: range)
                return
            }

            if trimmed == "---" || trimmed == "***" {
                storage.addAttributes(
                    [
                        .foregroundColor: NSColor.separatorColor,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .font: NSFont.systemFont(ofSize: 13)
                    ],
                    range: range
                )
                return
            }

            if let checklist = firstMatch(#"^(\s*[-*+]\s+\[[ xX]\]\s+)(.*)$"#, in: line) {
                applyChecklistStyle(storage, line: line, lineRange: range, match: checklist)
            } else if let bullet = firstMatch(#"^(\s*[-*+]\s+)(.*)$"#, in: line) {
                let marker = globalRange(bullet.range(at: 1), lineRange: range)
                if let glyphInfo = markerGlyphInfo(character: "•", baseString: String(line.prefix(1))) {
                    hide(storage, range: marker)
                    storage.addAttributes(
                        [
                            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                            .foregroundColor: NSColor.controlAccentColor,
                            .glyphInfo: glyphInfo
                        ],
                        range: NSRange(location: marker.location, length: 1)
                    )
                } else {
                    storage.addAttribute(
                        .foregroundColor,
                        value: NSColor.controlAccentColor,
                        range: marker
                    )
                }
            } else if let quote = firstMatch(#"^(\s*>\s+)(.*)$"#, in: line) {
                storage.addAttributes(
                    [
                        .foregroundColor: NSColor.controlAccentColor,
                        .font: NSFont.systemFont(ofSize: 15, weight: .semibold)
                    ],
                    range: globalRange(quote.range(at: 1), lineRange: range)
                )
                storage.addAttributes(
                    [
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .font: NSFontManager.shared.convert(
                            NSFont.systemFont(ofSize: 15),
                            toHaveTrait: .italicFontMask
                        )
                    ],
                    range: globalRange(quote.range(at: 2), lineRange: range)
                )
            }

            applyInlineStyles(storage, line: line, lineRange: range)
        }

        private func applyInlineStyles(
            _ storage: NSTextStorage,
            line: String,
            lineRange: NSRange
        ) {
            applyColorStyles(storage, line: line, lineRange: lineRange)
            for match in matches(#"\*\*(.+?)\*\*"#, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let content = globalRange(match.range(at: 1), lineRange: lineRange)
                hide(storage, range: NSRange(location: full.location, length: 2))
                hide(storage, range: NSRange(location: NSMaxRange(full) - 2, length: 2))
                storage.addAttribute(
                    .font,
                    value: NSFont.systemFont(ofSize: 15, weight: .bold),
                    range: content
                )
            }

            for match in matches(#"(?<!\*)\*([^*\n]+)\*(?!\*)"#, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let content = globalRange(match.range(at: 1), lineRange: lineRange)
                hide(storage, range: NSRange(location: full.location, length: 1))
                hide(storage, range: NSRange(location: NSMaxRange(full) - 1, length: 1))
                storage.addAttribute(
                    .font,
                    value: NSFontManager.shared.convert(
                        NSFont.systemFont(ofSize: 15),
                        toHaveTrait: .italicFontMask
                    ),
                    range: content
                )
            }

            for match in matches(#"`([^`\n]+)`"#, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let content = globalRange(match.range(at: 1), lineRange: lineRange)
                hide(storage, range: NSRange(location: full.location, length: 1))
                hide(storage, range: NSRange(location: NSMaxRange(full) - 1, length: 1))
                storage.addAttributes(
                    [
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                        .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.18)
                    ],
                    range: content
                )
            }

            for match in matches(#"~~(.+?)~~"#, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let content = globalRange(match.range(at: 1), lineRange: lineRange)
                hide(storage, range: NSRange(location: full.location, length: 2))
                hide(storage, range: NSRange(location: NSMaxRange(full) - 2, length: 2))
                storage.addAttribute(
                    .strikethroughStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: content
                )
            }

            for match in matches(#"==(.+?)=="#, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let content = globalRange(match.range(at: 1), lineRange: lineRange)
                hide(storage, range: NSRange(location: full.location, length: 2))
                hide(storage, range: NSRange(location: NSMaxRange(full) - 2, length: 2))
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor.systemYellow.withAlphaComponent(0.42),
                    range: content
                )
            }

            for match in matches(#"\{\{underline\|(.+?)\}\}"#, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let content = globalRange(match.range(at: 1), lineRange: lineRange)
                hide(storage, range: NSRange(location: full.location, length: content.location - full.location))
                hide(
                    storage,
                    range: NSRange(location: NSMaxRange(content), length: NSMaxRange(full) - NSMaxRange(content))
                )
                storage.addAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: content
                )
            }

            for match in matches(#"\[([^\]]+)\]\(([^)]+)\)"#, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let label = globalRange(match.range(at: 1), lineRange: lineRange)
                hide(storage, range: NSRange(location: full.location, length: label.location - full.location))
                hide(
                    storage,
                    range: NSRange(location: NSMaxRange(label), length: NSMaxRange(full) - NSMaxRange(label))
                )
                storage.addAttributes(
                    [
                        .foregroundColor: NSColor.linkColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ],
                    range: label
                )
            }
        }

        private func applyChecklistStyle(
            _ storage: NSTextStorage,
            line: String,
            lineRange: NSRange,
            match: NSTextCheckingResult
        ) {
            let marker = globalRange(match.range(at: 1), lineRange: lineRange)
            let item = globalRange(match.range(at: 2), lineRange: lineRange)
            let isChecked = line.range(of: "[x]", options: .caseInsensitive) != nil
            if let glyphInfo = markerGlyphInfo(
                character: isChecked ? "▣" : "□",
                baseString: String(line.prefix(1))
            ) {
                hide(storage, range: marker)
                storage.addAttributes(
                    [
                        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                        .foregroundColor: NSColor.controlAccentColor,
                        .glyphInfo: glyphInfo
                    ],
                    range: NSRange(location: marker.location, length: 1)
                )
            } else {
                storage.addAttributes(
                    [
                        .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                        .foregroundColor: NSColor.controlAccentColor
                    ],
                    range: marker
                )
            }
            if isChecked {
                storage.addAttributes(
                    [
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .foregroundColor: NSColor.secondaryLabelColor
                    ],
                    range: item
                )
            }
        }

        private func applyColorStyles(_ storage: NSTextStorage, line: String, lineRange: NSRange) {
            for match in matches(MarkdownColorFormatting.pattern, in: line) {
                let full = globalRange(match.range(at: 0), lineRange: lineRange)
                let content = globalRange(match.range(at: 2), lineRange: lineRange)
                let hex = (line as NSString).substring(with: match.range(at: 1))
                hide(storage, range: NSRange(location: full.location, length: content.location - full.location))
                hide(storage, range: NSRange(location: NSMaxRange(content), length: NSMaxRange(full) - NSMaxRange(content)))
                storage.addAttribute(.foregroundColor, value: nsColor(hex), range: content)
            }
        }

        private func nsColor(_ hex: String) -> NSColor {
            let value = UInt32(hex, radix: 16) ?? 0x20242B
            return NSColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }

        private func hide(_ storage: NSTextStorage, range: NSRange) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            storage.addAttributes(
                [
                    .foregroundColor: NSColor.clear,
                    .font: NSFont.systemFont(ofSize: 0.1)
                ],
                range: range
            )
        }

        private func firstMatch(_ pattern: String, in string: String) -> NSTextCheckingResult? {
            matches(pattern, in: string).first
        }

        private func matches(_ pattern: String, in string: String) -> [NSTextCheckingResult] {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
            return expression.matches(
                in: string,
                range: NSRange(location: 0, length: (string as NSString).length)
            )
        }

        private func globalRange(_ localRange: NSRange, lineRange: NSRange) -> NSRange {
            guard localRange.location != NSNotFound else { return localRange }
            return NSRange(location: lineRange.location + localRange.location, length: localRange.length)
        }

        private func markerGlyphInfo(character: Character, baseString: String) -> NSGlyphInfo? {
            let font = NSFont.systemFont(ofSize: 15, weight: .medium)
            guard let scalar = character.unicodeScalars.first else { return nil }
            var codeUnit = UniChar(scalar.value)
            var glyph = CGGlyph()
            guard CTFontGetGlyphsForCharacters(font as CTFont, &codeUnit, &glyph, 1) else {
                return nil
            }
            return NSGlyphInfo(glyph: NSGlyph(glyph), for: font, baseString: baseString)
        }
    }
}
#endif

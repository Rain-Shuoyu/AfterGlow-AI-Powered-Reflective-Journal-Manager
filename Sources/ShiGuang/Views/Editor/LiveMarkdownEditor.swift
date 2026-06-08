import SwiftUI
import AppKit

/// NSTextView-backed markdown editor that styles markdown syntax in
/// real-time as the user types. The goal is a "Typora-like" experience:
/// the user never sees the raw markup (`##`, `**`, `` ` ``, etc.) —
/// markers are kept in the text (so the cursor behaves normally) but
/// rendered with `foregroundColor: .clear`, while the body is styled
/// with the right font / size / weight / background.
///
/// Output of `text` binding is the **raw markdown** (markers included),
/// so saving to disk is unchanged.
///
/// Keyboard shortcuts (via the `MarkdownTextView` subclass):
///   ⌘B              — bold: wrap selection in `**…**`, or insert `****`
///   ⌘I              — italic: wrap selection in `*…*`
///   ⌘K              — link: wrap selection as `[…](url)`, or insert
///                      `[text](url)` placeholder
///   ⌘1 … ⌘6         — heading level 1-6 on the current line
///   ⌘0              — strip the heading prefix from the current line
struct LiveMarkdownEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        // Custom NSTextView subclass needs an explicit text container.
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = MarkdownTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        Self.configure(textView)
        textView.string = text
        LiveMarkdownEditor.applyMarkdownStyling(to: textView)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        // Make the textView the first responder once it's in a window.
        // Without this, NSViewRepresentable views are never automatically
        // focused, so the user has to click into the body to type — and
        // sometimes the click wouldn't even register (the bug the user
        // reported as "can't input / Cmd+B / Cmd+1 stop working").
        DispatchQueue.main.async {
            guard let window = scrollView.window else { return }
            window.makeFirstResponder(textView)
        }

        // Re-style on selection change so the cursor-aware marker
        // visibility kicks in as the user moves the caret (Typora-style
        // "markers fade in when cursor is on the segment, hide when
        // cursor moves away"). `textDidChange` only fires on text edits,
        // not on caret moves, so we need this explicit observer.
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: textView,
            queue: .main
        ) { [weak textView] _ in
            guard let tv = textView else { return }
            LiveMarkdownEditor.applyMarkdownStyling(to: tv)
        }
        context.coordinator.selectionObserver = observer

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            LiveMarkdownEditor.applyMarkdownStyling(to: textView)
            // Restore the selection, clamped to the new (possibly shorter)
            // string length so we don't crash on weird race conditions.
            let safeLoc = min(sel.location, text.count)
            let safeLen = min(sel.length, max(0, text.count - safeLoc))
            textView.setSelectedRange(NSRange(location: safeLoc, length: safeLen))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: LiveMarkdownEditor
        var selectionObserver: NSObjectProtocol?

        init(_ parent: LiveMarkdownEditor) { self.parent = parent }

        deinit {
            if let obs = selectionObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            LiveMarkdownEditor.applyMarkdownStyling(to: textView)
        }
    }

    // MARK: - Text view configuration

    /// Marker font — 0.01pt. Setting a tiny font (rather than only
    /// `foregroundColor: clear`) makes the layout manager allocate
    /// effectively zero horizontal space for the marker character. The
    /// cursor still moves through the marker's logical position — it
    /// just travels 0.01pt per char, invisible to the user. Without
    /// this, a hidden `##` would still push the line content to the
    /// right by 2 character widths.
    private static let markerFont = NSFont.systemFont(ofSize: 0.01)

    private static func configure(_ tv: NSTextView) {
        tv.isRichText = true
        tv.allowsUndo = true
        tv.font = .systemFont(ofSize: 15)
        tv.textColor = .labelColor
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.smartInsertDeleteEnabled = false
        // Continuous spell-check + autocorrect sometimes grabbed key
        // events before our Cmd+B / Cmd+1 handler could see them.
        // We can survive without live spell-check in a markdown editor.
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.usesFindBar = true
        tv.textContainerInset = NSSize(width: 12, height: 18)
        // Force the textView to fill the enclosing NSScrollView. Without
        // this, when the body is empty the textView shrinks to a single
        // line (~20pt) and the rest of the 420pt frame is dead space the
        // user can click but the textView never receives — they see
        // "no place to type". With `isVerticallyResizable = false` the
        // content scrolls *inside* the textView instead of growing it.
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = false
        tv.autoresizingMask = [.width, .height]
    }

    // MARK: - Styling pass

    /// Reentrancy guard. `NSTextView.didChangeSelectionNotification` is
    /// observed so we can re-style on caret moves (Typora-style marker
    /// visibility). But `applyMarkdownStyling` itself restores the
    /// selection via `setSelectedRange` at the end — which fires the
    /// same notification again, causing infinite recursion. This flag
    /// makes any nested call return immediately, breaking the cycle.
    private static var isApplyingStyling = false

    private static func applyMarkdownStyling(to tv: NSTextView) {
        // Re-entry guard — see comment above.
        if isApplyingStyling { return }
        isApplyingStyling = true
        defer { isApplyingStyling = false }

        guard let storage = tv.textStorage else { return }
        let sel = tv.selectedRange()
        let fullRange = NSRange(location: 0, length: storage.length)

        let bodyFont = NSFont.systemFont(ofSize: 15)
        let labelColor = NSColor.labelColor
        let monoFont = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
        let codeBg = NSColor.controlBackgroundColor

        // "Active" = the cursor is on this line/segment. When the cursor
        // is on or near a markdown segment, its marker characters (`**`,
        // `##`, `` ` ``, `-`, `>`, etc.) are shown at 40% white as a
        // visual hint. When the cursor moves elsewhere, the markers are
        // fully hidden — giving a true Typora-style live preview where
        // the user sees only the rendered output by default.
        let cursor = sel.location
        func markerColor(for range: NSRange) -> NSColor {
            let active = cursor >= range.location && cursor <= range.location + range.length
            return active
                ? NSColor.white.withAlphaComponent(0.40)
                : NSColor.clear
        }

        storage.beginEditing()
        storage.setAttributes([
            .font: bodyFont,
            .foregroundColor: labelColor
        ], range: fullRange)

        styleBlockElements(in: storage, markerColorFor: markerColor)
        styleInlineElements(in: storage, monoFont: monoFont, codeBg: codeBg, markerColorFor: markerColor)
        storage.endEditing()

        // Only restore selection when it actually changed — otherwise
        // the no-op setSelectedRange can still tickle NSTextView's
        // selection-change notification on some macOS versions, which
        // would feed back into the observer and re-enter this function
        // (the recursion the user just crashed on).
        let safeLoc = min(sel.location, storage.length)
        let safeLen = min(sel.length, max(0, storage.length - safeLoc))
        let safeSel = NSRange(location: safeLoc, length: safeLen)
        if safeSel.location != sel.location || safeSel.length != sel.length {
            tv.setSelectedRange(safeSel)
        }
    }

    // MARK: - Block styling

    private static func styleBlockElements(
        in storage: NSTextStorage,
        markerColorFor: (NSRange) -> NSColor
    ) {
        let text = storage.string
        let lines = text.components(separatedBy: "\n")
        var offset = 0
        for line in lines {
            let lineLen = (line as NSString).length
            let lineRange = NSRange(location: offset, length: lineLen)

            if let hashCount = atxHashCount(in: line), hashCount > 0 {
                let prefixLen = hashCount + 1
                let prefixRange = NSRange(location: lineRange.location, length: prefixLen)
                let bodyRange = NSRange(
                    location: lineRange.location + prefixLen,
                    length: max(0, lineRange.length - prefixLen)
                )
                storage.addAttribute(.font, value: markerFont, range: prefixRange)
                storage.addAttribute(
                    .foregroundColor,
                    value: markerColorFor(lineRange),
                    range: prefixRange
                )
                let fontSize: CGFloat = max(15, 28 - CGFloat(hashCount) * 3)
                storage.addAttribute(
                    .font,
                    value: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                    range: bodyRange
                )
            } else if isSetextUnderline(line) {
                let isH1 = line.trimmingCharacters(in: .whitespaces).first == "="
                storage.addAttribute(.font, value: markerFont, range: lineRange)
                storage.addAttribute(
                    .foregroundColor,
                    value: markerColorFor(lineRange),
                    range: lineRange
                )
                if lineRange.location > 0 {
                    let prevEnd = lineRange.location
                    let searchRange = NSRange(location: 0, length: max(0, prevEnd))
                    if let prevNewline = (text as NSString).rangeOfCharacter(
                        from: CharacterSet(charactersIn: "\n"),
                        options: .backwards,
                        range: searchRange
                    ) as NSRange?, prevNewline.location != NSNotFound {
                        let prevStart = prevNewline.location + 1
                        let prevRange = NSRange(
                            location: prevStart,
                            length: max(0, prevEnd - prevStart)
                        )
                        let fontSize: CGFloat = isH1 ? 24 : 20
                        storage.addAttribute(
                            .font,
                            value: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                            range: prevRange
                        )
                    }
                }
            } else if let m = firstMatch(in: line, pattern: #"^(\s*)[-*+]\s+"#) {
                let matchLen = (m as NSString).length
                let leadingSpaces = (m as NSString).range(of: #"^\s*"#).length
                let prefixRange = NSRange(location: lineRange.location, length: matchLen)
                let bodyRange = NSRange(
                    location: lineRange.location + matchLen,
                    length: max(0, lineRange.length - matchLen)
                )
                storage.addAttribute(.font, value: markerFont, range: prefixRange)
                storage.addAttribute(
                    .foregroundColor,
                    value: markerColorFor(lineRange),
                    range: prefixRange
                )
                let para = NSMutableParagraphStyle()
                let indent = CGFloat(leadingSpaces) * 8 + 16
                para.headIndent = indent
                para.firstLineHeadIndent = indent - 8
                storage.addAttribute(.paragraphStyle, value: para, range: bodyRange)
            } else if let m = firstMatch(in: line, pattern: #"^(\s*)\d+\.\s+"#) {
                let matchLen = (m as NSString).length
                let prefixRange = NSRange(location: lineRange.location, length: matchLen)
                let bodyRange = NSRange(
                    location: lineRange.location + matchLen,
                    length: max(0, lineRange.length - matchLen)
                )
                storage.addAttribute(.font, value: markerFont, range: prefixRange)
                storage.addAttribute(
                    .foregroundColor,
                    value: markerColorFor(lineRange),
                    range: prefixRange
                )
                let para = NSMutableParagraphStyle()
                para.headIndent = 24
                para.firstLineHeadIndent = 24
                storage.addAttribute(.paragraphStyle, value: para, range: bodyRange)
            } else if firstMatch(in: line, pattern: #"^>\s+"#) != nil {
                if let m = firstMatch(in: line, pattern: #"^>\s+"#) {
                    let matchLen = (m as NSString).length
                    let prefixRange = NSRange(location: lineRange.location, length: matchLen)
                    let bodyRange = NSRange(
                        location: lineRange.location + matchLen,
                        length: max(0, lineRange.length - matchLen)
                    )
                    storage.addAttribute(.font, value: markerFont, range: prefixRange)
                    storage.addAttribute(
                        .foregroundColor,
                        value: markerColorFor(lineRange),
                        range: prefixRange
                    )
                    if let currentFont = storage.attribute(
                        .font, at: bodyRange.location, effectiveRange: nil
                    ) as? NSFont {
                        storage.addAttribute(.font, value: currentFont.withItalics(), range: bodyRange)
                    }
                    storage.addAttribute(
                        .foregroundColor,
                        value: NSColor.secondaryLabelColor,
                        range: bodyRange
                    )
                }
            }

            offset += lineLen + 1
        }
    }

    // MARK: - Inline styling

    private static func styleInlineElements(
        in storage: NSTextStorage,
        monoFont: NSFont,
        codeBg: NSColor,
        markerColorFor: (NSRange) -> NSColor
    ) {
        let text = storage.string
        let fullRange = NSRange(location: 0, length: text.utf16.count)

        if let regex = try? NSRegularExpression(pattern: #"(\*\*|__)([^*_]+?)(\*\*|__)"#) {
            for match in regex.matches(in: text, options: [], range: fullRange) {
                let firstMarker = match.range(at: 1)
                let bodyRange = match.range(at: 2)
                let secondMarker = match.range(at: 3)
                let mc = markerColorFor(match.range)
                storage.addAttribute(.font, value: markerFont, range: firstMarker)
                storage.addAttribute(.font, value: markerFont, range: secondMarker)
                storage.addAttribute(.foregroundColor, value: mc, range: firstMarker)
                storage.addAttribute(.foregroundColor, value: mc, range: secondMarker)
                if let f = storage.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? NSFont {
                    let bold = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask)
                    storage.addAttribute(.font, value: bold, range: bodyRange)
                } else {
                    storage.addAttribute(
                        .font,
                        value: NSFont.boldSystemFont(ofSize: 15),
                        range: bodyRange
                    )
                }
            }
        }

        if let regex = try? NSRegularExpression(
            pattern: #"(?<!\*)\*([^*\n]+?)\*(?!\*)|(?<!_)_(?!_)([^_\n]+?)_(?!_)"#
        ) {
            for match in regex.matches(in: text, options: [], range: fullRange) {
                let full = match.range
                guard full.length >= 3 else { continue }
                let marker1 = NSRange(location: full.location, length: 1)
                let marker2 = NSRange(location: full.location + full.length - 1, length: 1)
                let body = NSRange(location: full.location + 1, length: full.length - 2)
                let mc = markerColorFor(full)
                storage.addAttribute(.font, value: markerFont, range: marker1)
                storage.addAttribute(.font, value: markerFont, range: marker2)
                storage.addAttribute(.foregroundColor, value: mc, range: marker1)
                storage.addAttribute(.foregroundColor, value: mc, range: marker2)
                if let f = storage.attribute(.font, at: body.location, effectiveRange: nil) as? NSFont {
                    storage.addAttribute(.font, value: f.withItalics(), range: body)
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: #"`([^`\n]+?)`"#) {
            for match in regex.matches(in: text, options: [], range: fullRange) {
                let r = match.range
                let body = match.range(at: 1)
                let firstTick = NSRange(location: r.location, length: 1)
                let lastTick = NSRange(location: r.location + r.length - 1, length: 1)
                storage.addAttribute(.font, value: monoFont, range: body)
                storage.addAttribute(.backgroundColor, value: codeBg, range: body)
                storage.addAttribute(.font, value: markerFont, range: firstTick)
                storage.addAttribute(.font, value: markerFont, range: lastTick)
                let mc = markerColorFor(r)
                storage.addAttribute(.foregroundColor, value: mc, range: firstTick)
                storage.addAttribute(.foregroundColor, value: mc, range: lastTick)
            }
        }
    }

    // MARK: - Regex helpers

    private static func firstMatch(in line: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let m = regex.firstMatch(in: line, options: [], range: range) else { return nil }
        return nsLine.substring(with: m.range)
    }

    private static func atxHashCount(in line: String) -> Int? {
        var i = line.startIndex
        var n = 0
        while i < line.endIndex, line[i] == "#", n < 6 {
            n += 1
            i = line.index(after: i)
        }
        guard n > 0 else { return nil }
        guard i == line.endIndex || line[i] == " " else { return nil }
        return n
    }

    private static func isSetextUnderline(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        let first = t.first!
        guard first == "=" || first == "-" else { return false }
        return t.allSatisfy { $0 == first }
    }
}

// MARK: - Custom NSTextView with markdown keyboard shortcuts

/// `NSTextView` subclass that handles the editor's keyboard shortcuts.
/// Standard `NSTextView` already routes ⌘C / ⌘V / ⌘X / ⌘Z etc. — we only
/// intercept the markdown formatting ones. Anything we don't handle falls
/// through to `super.keyDown(with:)` so the normal typing path stays
/// intact (and the existing `textDidChange` flow re-applies styling).
final class MarkdownTextView: NSTextView {

    override func keyDown(with event: NSEvent) {
        // Only intercept ⌘-modified shortcuts. Plain typing routes
        // through `interpretKeyEvents(_:)` — the standard NSTextView
        // editing pipeline — instead of `super.keyDown`. The reason:
        // after we override keyDown, calling `super.keyDown` for
        // unhandled keys doesn't always run the full interpretKeyEvents
        // chain on macOS 26, which manifested as "subsequent typing
        // stopped working" right after the user pressed ⌘B / ⌘1.
        guard event.modifierFlags.contains(.command) else {
            interpretKeyEvents([event])
            return
        }

        // charactersIgnoringModifiers is what the user pressed, ignoring
        // ⌘ / ⇧ / ⌥. Lowercased so ⇧B still matches.
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch key {
        case "b":
            wrap(prefix: "**", suffix: "**")
        case "i":
            wrap(prefix: "*", suffix: "*")
        case "k":
            insertLink()
        case "1", "2", "3", "4", "5", "6":
            if let level = Int(key) {
                setHeading(level: level)
            } else {
                interpretKeyEvents([event])
            }
        case "0":
            clearHeading()
        default:
            interpretKeyEvents([event])
        }
    }

    // MARK: - Shortcut actions

    /// Wrap the current selection in `prefix` / `suffix`. If no selection,
    /// insert `prefix + suffix` and place the caret in the middle so the
    /// user can just start typing.
    private func wrap(prefix: String, suffix: String) {
        let sel = selectedRange()
        let nsString = string as NSString
        if sel.length == 0 {
            let placeholder = "\(prefix)\(suffix)"
            insertText(placeholder, replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + prefix.count, length: 0))
        } else {
            let selectedText = nsString.substring(with: sel)
            let newText = "\(prefix)\(selectedText)\(suffix)"
            insertText(newText, replacementRange: sel)
            setSelectedRange(NSRange(
                location: sel.location + prefix.count,
                length: sel.length
            ))
        }
    }

    /// Apply a heading level (1-6) to the current line. Replaces any
    /// existing heading prefix on that line.
    private func setHeading(level: Int) {
        let cursor = selectedRange().location
        let nsString = string as NSString
        let lineRange = currentLineRange(at: cursor)
        let lineText = nsString.substring(with: lineRange)
        let cleaned = lineText.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        let prefix = String(repeating: "#", count: level) + " "
        let newText = prefix + cleaned
        insertText(newText, replacementRange: lineRange)
        // Place cursor at end of the new line so the user can type the
        // heading text immediately.
        setSelectedRange(NSRange(
            location: lineRange.location + newText.count,
            length: 0
        ))
    }

    /// Strip the heading prefix from the current line (⌘0).
    private func clearHeading() {
        let cursor = selectedRange().location
        let nsString = string as NSString
        let lineRange = currentLineRange(at: cursor)
        let lineText = nsString.substring(with: lineRange)
        let cleaned = lineText.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        insertText(cleaned, replacementRange: lineRange)
    }

    /// Insert a markdown link. With selection, wrap as `[sel](url)` and
    /// select the `url` part. Without selection, insert `[text](url)`
    /// and select `text` so the user can just type the link text.
    private func insertLink() {
        let sel = selectedRange()
        let nsString = string as NSString
        if sel.length == 0 {
            let placeholder = "[text](url)"
            insertText(placeholder, replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + 1, length: 4))
        } else {
            let selectedText = nsString.substring(with: sel)
            let newText = "[\(selectedText)](url)"
            insertText(newText, replacementRange: sel)
            let urlStart = sel.location + 1 + selectedText.count + 2
            setSelectedRange(NSRange(location: urlStart, length: 3))
        }
    }

    // MARK: - Cursor movement (skip hidden markers)

    /// Heuristic: is the character at `loc` rendered with the marker
    /// font (0.01pt)? If yes, it's a markdown marker that the user
    /// can't actually see in the layout — so the caret should skip
    /// over it instead of landing inside it (where it'd appear to
    /// be stuck between two invisible chars).
    private func isMarkerAt(_ loc: Int) -> Bool {
        guard let storage = textStorage, loc >= 0, loc < storage.length else {
            return false
        }
        let attrs = storage.attributes(at: loc, effectiveRange: nil)
        if let f = attrs[.font] as? NSFont {
            return f.pointSize < 1
        }
        return false
    }

    override func moveRight(_ sender: Any?) {
        // If the user is holding shift (extending selection) or there's
        // already a non-empty selection, fall through to the standard
        // NSTextView behavior — we only override the bare arrow case.
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        let sel = selectedRange()
        if shift || sel.length > 0 {
            super.moveRight(sender)
            return
        }
        // No shift, no selection: walk right, skipping over marker
        // characters, until we hit a real glyph or the end of buffer.
        var newLoc = sel.location + 1
        while newLoc < (textStorage?.length ?? 0), isMarkerAt(newLoc) {
            newLoc += 1
        }
        newLoc = min(newLoc, textStorage?.length ?? 0)
        setSelectedRange(NSRange(location: newLoc, length: 0))
    }

    override func moveLeft(_ sender: Any?) {
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        let sel = selectedRange()
        if shift || sel.length > 0 {
            super.moveLeft(sender)
            return
        }
        var newLoc = sel.location - 1
        while newLoc >= 0, isMarkerAt(newLoc) {
            newLoc -= 1
        }
        newLoc = max(0, newLoc)
        setSelectedRange(NSRange(location: newLoc, length: 0))
    }

    // MARK: - Line helpers

    /// The range of the line containing `cursor`, not including the
    /// trailing newline. If the cursor is past the end of the string,
    /// it returns the last line.
    private func currentLineRange(at cursor: Int) -> NSRange {
        let nsString = string as NSString
        let safeCursor = min(max(0, cursor), nsString.length)
        var lineStart = safeCursor
        while lineStart > 0 {
            let prev = nsString.substring(with: NSRange(location: lineStart - 1, length: 1))
            if prev == "\n" { break }
            lineStart -= 1
        }
        let restRange = NSRange(
            location: safeCursor,
            length: max(0, nsString.length - safeCursor)
        )
        let lineEnd = nsString.range(of: "\n", range: restRange)
        let lineLength: Int
        if lineEnd.location == NSNotFound {
            lineLength = nsString.length - lineStart
        } else {
            lineLength = lineEnd.location - lineStart
        }
        return NSRange(location: lineStart, length: lineLength)
    }
}

// MARK: - NSFont italic helper

extension NSFont {
    func withItalics() -> NSFont {
        let traits = fontDescriptor.symbolicTraits
        let descriptor = fontDescriptor.withSymbolicTraits(traits.union(.italic))
        return NSFont(descriptor: descriptor, size: 0) ?? self
    }
}

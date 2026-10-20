import SwiftUI
import AppKit

/// The notes editor: an AppKit text view (an input, like the fields) with Wave's font and colors, no chrome,
/// driven by the format bar. Content round-trips as RTF; the plain text is kept beside it.
@Observable final class RichEditor {
    weak var textView: NSTextView?
    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var block: Block = .body
    enum Block { case body, h1, h2, code, bullets, numbers }

    static let bodyFont = NSFont(name: "Instrument Sans", size: 16) ?? .systemFont(ofSize: 16)
    static func font(_ size: CGFloat, semibold: Bool) -> NSFont {
        NSFont(name: semibold ? "InstrumentSans-Regular_SemiBold" : "Instrument Sans", size: size) ?? .systemFont(ofSize: size, weight: semibold ? .semibold : .regular)
    }
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

    private var storage: NSTextStorage? { textView?.textStorage }
    private var selection: NSRange { textView?.selectedRange() ?? NSRange(location: 0, length: 0) }
    private var paragraphs: NSRange { (storage?.string as NSString? ?? "").paragraphRange(for: selection) }

    /// Reads the attributes at the caret so the bar shows the current state.
    func refresh() {
        guard let textView, let storage else { return }
        let location = max(0, min(selection.location, storage.length - 1))
        let attrs = storage.length > 0 ? storage.attributes(at: location, effectiveRange: nil) : textView.typingAttributes
        let font = attrs[.font] as? NSFont ?? Self.bodyFont
        bold = font.fontDescriptor.symbolicTraits.contains(.bold) || font.fontName.contains("SemiBold") || font.fontName.contains("Bold")
        italic = font.fontDescriptor.symbolicTraits.contains(.italic)
        underline = (attrs[.underlineStyle] as? Int ?? 0) != 0
        strike = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
        let style = attrs[.paragraphStyle] as? NSParagraphStyle
        if font.isFixedPitch { block = .code }
        else if let list = style?.textLists.first { block = list.markerFormat == .decimal ? .numbers : .bullets }
        else if font.pointSize >= 26 { block = .h1 }
        else if font.pointSize >= 20 { block = .h2 }
        else { block = .body }
    }

    func toggleBold() { toggleTrait(.boldFontMask, off: .unboldFontMask) }
    func toggleItalic() { toggleTrait(.italicFontMask, off: .unitalicFontMask) }
    func toggleUnderline() { toggle(.underlineStyle, on: NSUnderlineStyle.single.rawValue) }
    func toggleStrike() { toggle(.strikethroughStyle, on: NSUnderlineStyle.single.rawValue) }

    func set(_ block: Block) {
        guard let textView, let storage else { return }
        let range = paragraphs
        let style = NSMutableParagraphStyle()
        var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: Theme.nsInk, .backgroundColor: NSColor.clear]
        switch block {
        case .body: attrs[.font] = Self.bodyFont
        case .h1: attrs[.font] = Self.font(26, semibold: true)
        case .h2: attrs[.font] = Self.font(20, semibold: true)
        case .code: attrs[.font] = Self.codeFont; attrs[.backgroundColor] = Theme.nsSurface
        case .bullets, .numbers:
            attrs[.font] = Self.bodyFont
            style.textLists = [NSTextList(markerFormat: block == .bullets ? .disc : .decimal, options: 0)]
            style.headIndent = 24
        }
        style.paragraphSpacing = block == .h1 || block == .h2 ? 6 : 2
        attrs[.paragraphStyle] = style
        textView.shouldChangeText(in: range, replacementString: nil)
        storage.beginEditing()
        if range.length > 0 { storage.addAttributes(attrs, range: range) }
        storage.endEditing()
        textView.didChangeText()
        textView.typingAttributes = attrs
        self.block = block
    }

    private func toggleTrait(_ on: NSFontTraitMask, off: NSFontTraitMask) {
        guard let textView, let storage else { return }
        let isOn = on == .boldFontMask ? bold : italic
        let mask = isOn ? off : on
        if selection.length > 0 {
            textView.shouldChangeText(in: selection, replacementString: nil)
            storage.beginEditing()
            storage.applyFontTraits(mask, range: selection)
            storage.endEditing()
            textView.didChangeText()
        }
        var typing = textView.typingAttributes
        if let font = typing[.font] as? NSFont { typing[.font] = NSFontManager.shared.convert(font, toHaveTrait: mask) }
        textView.typingAttributes = typing
        refresh()
    }

    private func toggle(_ key: NSAttributedString.Key, on value: Int) {
        guard let textView, let storage else { return }
        let isOn = key == .underlineStyle ? underline : strike
        if selection.length > 0 {
            textView.shouldChangeText(in: selection, replacementString: nil)
            storage.beginEditing()
            if isOn { storage.removeAttribute(key, range: selection) } else { storage.addAttribute(key, value: value, range: selection) }
            storage.endEditing()
            textView.didChangeText()
        }
        var typing = textView.typingAttributes
        if isOn { typing.removeValue(forKey: key) } else { typing[key] = value }
        textView.typingAttributes = typing
        refresh()
    }
}

struct RichTextView: NSViewRepresentable {
    let editor: RichEditor
    let noteID: String
    let initialRTF: Data?
    let initialText: String
    let onChange: (Data, String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        textView.drawsBackground = false
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.font = RichEditor.bodyFont
        textView.textColor = Theme.nsInk
        textView.insertionPointColor = Theme.nsInk
        textView.delegate = context.coordinator
        load(textView)
        context.coordinator.loaded = noteID
        editor.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, context.coordinator.loaded != noteID else { return }
        load(textView)
        context.coordinator.loaded = noteID
        editor.textView = textView
    }

    private func load(_ textView: NSTextView) {
        let base: [NSAttributedString.Key: Any] = [.font: RichEditor.bodyFont, .foregroundColor: Theme.nsInk]
        if let rtf = initialRTF, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributed)
            // RTF carries fixed colors; put the dynamic ink back on everything that is not a code block.
            textView.textStorage?.addAttribute(.foregroundColor, value: Theme.nsInk, range: NSRange(location: 0, length: attributed.length))
        } else {
            textView.textStorage?.setAttributedString(NSAttributedString(string: initialText, attributes: base))
        }
        textView.typingAttributes = base
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextView
        var loaded = ""
        init(_ parent: RichTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView, let storage = textView.textStorage else { return }
            let rtf = storage.rtf(from: NSRange(location: 0, length: storage.length), documentAttributes: [:]) ?? Data()
            parent.onChange(rtf, storage.string)
            parent.editor.refresh()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.editor.refresh()
        }
    }
}

/// Bold, italic, underline, strikethrough, then the block styles. Pills like the rest of the app.
struct FormatBar: View {
    let editor: RichEditor

    var body: some View {
        HStack(spacing: 6) {
            toggle("text-b", editor.bold, "b") { editor.toggleBold() }
            toggle("text-italic", editor.italic, "i") { editor.toggleItalic() }
            toggle("text-underline", editor.underline, "u") { editor.toggleUnderline() }
            toggle("text-strikethrough", editor.strike, nil) { editor.toggleStrike() }
            Rectangle().fill(Theme.ink.opacity(0.12)).frame(width: 1, height: 18).padding(.horizontal, 4)
            block("text-t", .body, "Paragraph")
            block("text-h-one", .h1, "Heading 1")
            block("text-h-two", .h2, "Heading 2")
            block("list-bullets", .bullets, "Bulleted list")
            block("list-numbers", .numbers, "Numbered list")
            block("code", .code, "Code block")
            Spacer()
        }
    }

    private func toggle(_ icon: String, _ on: Bool, _ key: Character?, _ action: @escaping () -> Void) -> some View {
        let button = Button(action: action) { pill(icon, on) }.buttonStyle(PressStyle())
        return Group {
            if let key { button.keyboardShortcut(KeyEquivalent(key), modifiers: .command) } else { button }
        }
    }

    private func block(_ icon: String, _ block: RichEditor.Block, _ name: String) -> some View {
        Button { editor.set(block) } label: { pill(icon, editor.block == block) }.buttonStyle(PressStyle())
    }

    private func pill(_ icon: String, _ on: Bool) -> some View {
        Icon(icon, size: 16, color: on ? Theme.paper : Theme.ink)
            .frame(width: 32, height: 32)
            .background(on ? Theme.ink : Theme.chip, in: RoundedRectangle(cornerRadius: 10))
    }
}

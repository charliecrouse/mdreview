import AppKit
import MDReviewCore
import SwiftUI

struct ReaderView: NSViewRepresentable {
    let text: NSAttributedString
    let comments: [ReviewComment]
    let focused: ReviewComment.ID?
    let scrollTarget: NSRange?
    let onSelect: @MainActor (NSRange) -> Void
    let onComment: @MainActor () -> Void
    let onScrolled: @MainActor @Sendable () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 for simple layout-manager highlights and scrolling.
        let textView = PaperTextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false  // the SwiftUI frost behind shows through
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.usesFindBar = true
        textView.delegate = context.coordinator
        textView.setAccessibilityIdentifier("reader")
        textView.unregisterDraggedTypes()  // let file drops reach the SwiftUI drop target

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        if coordinator.shownText !== text {
            textView.textStorage?.setAttributedString(text)
            coordinator.shownText = text
            textView.scroll(.zero)
        }
        coordinator.highlight(comments, focused: focused)
        if let target = scrollTarget {
            coordinator.reveal(target)
            DispatchQueue.main.async(execute: onScrolled)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReaderView?
        weak var textView: NSTextView?
        var shownText: NSAttributedString?

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            parent?.onSelect(textView.selectedRange())
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            let item = NSMenuItem(title: "Add Comment", action: #selector(addComment), keyEquivalent: "")
            item.target = self
            item.isEnabled = view.selectedRange().length > 0
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
            return menu
        }

        @objc func addComment() { parent?.onComment() }

        func highlight(_ comments: [ReviewComment], focused: ReviewComment.ID?) {
            guard let textView, let layout = textView.layoutManager else { return }
            let length = textView.textStorage?.length ?? 0
            let all = NSRange(location: 0, length: length)
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
            layout.removeTemporaryAttribute(.underlineStyle, forCharacterRange: all)
            for comment in comments where NSMaxRange(comment.range) <= length {
                layout.addTemporaryAttributes(
                    [
                        .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(
                            comment.id == focused ? 0.32 : 0.16),
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: NSColor.controlAccentColor,
                    ], forCharacterRange: comment.range)
            }
        }

        func reveal(_ range: NSRange) {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer,
                NSMaxRange(range) <= (textView.textStorage?.length ?? 0)
            else { return }
            layout.ensureLayout(for: container)
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            textView.scroll(NSPoint(x: 0, y: max(0, rect.minY + textView.textContainerOrigin.y - 24)))
            if range.length > 0 {
                textView.setSelectedRange(range)
                textView.showFindIndicator(for: range)
            }
        }
    }
}

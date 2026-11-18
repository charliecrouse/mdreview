import AppKit

/// Keeps a centered reading measure of about 720 pt however wide the window gets.
final class PaperTextView: NSTextView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let inset = NSSize(width: max(40, (newSize.width - 720) / 2), height: 36)
        if textContainerInset != inset { textContainerInset = inset }
    }

    /// The first line of the selection in `view`'s coordinates, or nil with no selection.
    func selectionRect(in view: NSView) -> CGRect? {
        let range = selectedRange()
        guard range.length > 0, let window else { return nil }
        let onScreen = firstRect(forCharacterRange: range, actualRange: nil)
        return view.convert(window.convertFromScreen(onScreen), from: nil)
    }
}

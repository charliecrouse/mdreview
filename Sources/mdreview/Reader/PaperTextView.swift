import AppKit

/// Keeps a centered reading measure of about 720 pt however wide the window gets.
final class PaperTextView: NSTextView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let inset = NSSize(width: max(40, (newSize.width - 720) / 2), height: 36)
        if textContainerInset != inset { textContainerInset = inset }
    }
}

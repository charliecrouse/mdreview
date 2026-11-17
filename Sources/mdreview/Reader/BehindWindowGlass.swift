import AppKit
import SwiftUI

/// Behind-window material: the desktop shows through the window, blurred.
/// Liquid Glass only refracts in-window content, so the native floating sidebar sits on top of
/// this. AppKit swaps in an opaque fill when Reduce Transparency is on.
/// The material stays active when the window isn't key: a review window usually sits beside the
/// agent's terminal, and the default (flatten to gray when inactive) would make it look opaque.
struct BehindWindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

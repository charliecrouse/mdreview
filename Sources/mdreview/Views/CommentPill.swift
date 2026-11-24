import SwiftUI

/// A glass button floating by the selected text, so commenting doesn't need the inspector.
struct CommentPill: View {
    let model: ReviewModel
    let selection: CGRect

    var body: some View {
        Button {
            model.addComment()
        } label: {
            Label("Comment", systemImage: "text.bubble")
            Text("⌥⌘M").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect()
        .fixedSize()
        .offset(x: max(8, selection.minX), y: selection.minY < 44 ? selection.maxY + 6 : selection.minY - 38)
        .accessibilityIdentifier("commentPill")
    }
}

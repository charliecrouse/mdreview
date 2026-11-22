import MDReviewCore
import SwiftUI

struct CommentsInspector: View {
    @Bindable var model: ReviewModel
    @FocusState private var focusedField: ReviewComment.ID?

    var body: some View {
        VStack(spacing: 0) {
            if model.visibleComments.isEmpty {
                ContentUnavailableView(
                    model.comments.isEmpty ? "No comments" : "No \(model.filter.rawValue.lowercased()) comments",
                    systemImage: "text.bubble",
                    description: Text(
                        model.comments.isEmpty
                            ? "Select text in the document, then press ⌥⌘M or right-click → Add Comment."
                            : "Choose another filter above."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array($model.comments.enumerated()), id: \.element.id) { index, $comment in
                            if model.filter.includes(comment) {
                                CommentCard(
                                    number: index + 1,
                                    comment: $comment,
                                    isFocused: model.focusedComment == comment.id,
                                    focusedField: $focusedField,
                                    onSelect: { model.reveal(comment) },
                                    onDelete: { model.delete(comment.id) },
                                    onResolve: { model.setResolved($0, for: comment.id) }
                                )
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)  // glass fills the column even when empty
        .safeAreaInset(edge: .top, spacing: 0) { InspectorHeader(model: model) }
        .background(BehindWindowGlass().ignoresSafeArea())
        .onChange(of: model.focusedComment) { _, id in focusedField = id }
    }
}

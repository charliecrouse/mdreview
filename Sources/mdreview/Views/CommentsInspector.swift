import MDReviewCore
import SwiftUI

struct CommentsInspector: View {
    @Bindable var model: ReviewModel
    @FocusState private var focusedField: ReviewComment.ID?

    var body: some View {
        VStack(spacing: 0) {
            if model.comments.isEmpty {
                ContentUnavailableView(
                    "No comments", systemImage: "text.bubble",
                    description: Text("Select text in the document, then press ⌥⌘M or right-click → Add Comment."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array($model.comments.enumerated()), id: \.element.id) { index, $comment in
                            CommentCard(
                                number: index + 1,
                                comment: $comment,
                                isFocused: model.focusedComment == comment.id,
                                focusedField: $focusedField,
                                onSelect: { model.reveal(comment) },
                                onDelete: { model.delete(comment.id) }
                            )
                        }
                    }
                    .padding(12)
                }
            }
            if let status = model.status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)  // glass fills the column even when empty
        .background(BehindWindowGlass().ignoresSafeArea())
        .onChange(of: model.focusedComment) { _, id in focusedField = id }
    }
}

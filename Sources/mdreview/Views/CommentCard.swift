import MDReviewCore
import SwiftUI

struct CommentCard: View {
    let number: Int
    @Binding var comment: ReviewComment
    let isFocused: Bool
    var focusedField: FocusState<ReviewComment.ID?>.Binding
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("\(number)").font(.caption2.bold()).foregroundStyle(.white)
                    .frame(width: 18, height: 18).background(Circle().fill(.tint))
                Text("Line\(comment.lines.count == 1 ? "" : "s") \(comment.lineLabel)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label("Delete comment", systemImage: "trash").labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Delete comment")
            }
            Text(comment.quote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .padding(.leading, 8)
                .overlay(alignment: .leading) { Rectangle().fill(.tint).frame(width: 2) }
            TextField("Add a comment…", text: $comment.text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...10)
                .focused(focusedField, equals: comment.id)
                .accessibilityIdentifier("commentField")
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(
                isFocused ? Color.accentColor : Color.secondary.opacity(0.2))
        )
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
        .accessibilityAddTraits(.isButton)
    }
}

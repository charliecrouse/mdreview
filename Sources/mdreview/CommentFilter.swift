import MDReviewCore

enum CommentFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case open = "Open"
    case outdated = "Outdated"

    var id: Self { self }

    func includes(_ comment: ReviewComment) -> Bool {
        switch self {
        case .all: true
        case .open: !comment.isOutdated
        case .outdated: comment.isOutdated
        }
    }
}

import Foundation

/// Every change to a file's comments names its comment by id, never by position, so a caller still holding a
/// comment that was just deleted, or that left with its file, changes nothing instead of indexing a stale slot.
extension [ReviewComment] {
    public mutating func setText(_ text: String, for id: ReviewComment.ID) {
        edit(id) { $0.text = text }
    }

    /// The reviewer's call on whether the comment is handled; reopening also withdraws the agent's claim.
    public mutating func setResolved(_ resolved: Bool, for id: ReviewComment.ID) {
        edit(id) {
            $0.isResolved = resolved
            if !resolved { $0.agentSaysDone = false }
        }
    }

    public mutating func delete(_ id: ReviewComment.ID) {
        removeAll { $0.id == id }
    }

    /// Attaches each reply to the comment whose id starts with the reply's id. A reply naming no comment,
    /// or more than one, is dropped. A reply only proposes the comment is handled; it never resolves it.
    public mutating func apply(_ replies: [ReviewStore.Reply]) {
        for reply in replies {
            let id = reply.id.lowercased()
            let matches = filter { $0.id.uuidString.lowercased().hasPrefix(id) }
            guard id.count >= 4, matches.count == 1, let match = matches.first else { continue }
            edit(match.id) {
                $0.agentReply = reply.text
                $0.agentSaysDone = reply.resolve
            }
        }
    }

    private mutating func edit(_ id: ReviewComment.ID, _ change: (inout ReviewComment) -> Void) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        change(&self[index])
    }
}

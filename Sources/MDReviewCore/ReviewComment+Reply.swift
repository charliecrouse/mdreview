import Foundation

extension [ReviewComment] {
    /// Attaches each reply to the comment whose id starts with the reply's id. A reply naming no comment,
    /// or more than one, is dropped. A reply only proposes the comment is handled; it never resolves it.
    public mutating func apply(_ replies: [ReviewStore.Reply]) {
        for reply in replies {
            let id = reply.id.lowercased()
            let matches = indices.filter { self[$0].id.uuidString.lowercased().hasPrefix(id) }
            guard id.count >= 4, matches.count == 1, let index = matches.first else { continue }
            self[index].agentReply = reply.text
            self[index].agentSaysDone = reply.resolve
        }
    }
}

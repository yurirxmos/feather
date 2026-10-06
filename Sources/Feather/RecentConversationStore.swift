import FeatherCore
import Foundation

/// Keeps the last few conversations in Application Support, on this computer only, so ↑ in the
/// panel can bring them back after Feather restarts. Screen context is never written here.
@MainActor
final class RecentConversationStore {
    static let shared = RecentConversationStore()

    private(set) var conversations: [SavedConversation]
    private let fileURL: URL?

    init(fileURL: URL? = RecentConversationStore.defaultFileURL) {
        self.fileURL = fileURL
        conversations = RecentConversations.decode(fileURL.flatMap { try? Data(contentsOf: $0) })
    }

    func save(_ conversation: SavedConversation, restoredFrom original: SavedConversation?) {
        let updated = RecentConversations.saving(conversation, restoredFrom: original, in: conversations)
        guard updated != conversations else { return }
        conversations = updated
        guard let fileURL, let data = RecentConversations.encode(updated) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Feather could not save recent conversations: \(error.localizedDescription)")
        }
    }

    nonisolated private static var defaultFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Feather", isDirectory: true)
            .appendingPathComponent("recent-conversations.json")
    }
}

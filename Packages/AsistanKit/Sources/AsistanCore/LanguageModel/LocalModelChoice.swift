/// A conversation model on this Mac, persisted as "<server>:<model id>".
public struct LocalModelChoice: Sendable, Hashable {
    public enum Server: String, Sendable, CaseIterable {
        case lmStudio = "lmstudio"
        case vmlx
        /// Downloaded by Bilge and run inside the app; the id is a `ModelCatalog` entry.
        case builtIn = "builtin"
    }

    public let server: Server
    public let modelID: String

    public init(server: Server, modelID: String) {
        self.server = server
        self.modelID = modelID
    }

    /// Values saved before servers were distinguished hold a bare LM Studio model id.
    public init?(storageKey: String) {
        let parts = storageKey.split(separator: ":", maxSplits: 1).map(String.init)
        if parts.count == 2, let server = Server(rawValue: parts[0]), !parts[1].isEmpty {
            self.init(server: server, modelID: parts[1])
        } else if !storageKey.isEmpty, !storageKey.contains(":") {
            self.init(server: .lmStudio, modelID: storageKey)
        } else {
            return nil
        }
    }

    public var storageKey: String { "\(server.rawValue):\(modelID)" }
}

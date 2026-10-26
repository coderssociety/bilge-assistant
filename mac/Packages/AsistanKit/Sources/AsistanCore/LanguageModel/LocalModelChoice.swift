/// A conversation model on this Mac, persisted as "<server>:<model id>".
public struct LocalModelChoice: Sendable, Hashable {
    public enum Server: String, Sendable, CaseIterable {
        case lmStudio = "lmstudio"
        case vmlx
        /// Downloaded by Bilge and run inside the app; the id is a `ModelCatalog` entry.
        case builtIn = "builtin"
        /// An MLX model the user put in Bilge's own models folder; the id is its folder name.
        case custom = "mlx"
        /// An MLX model found elsewhere on the Mac (LM Studio, the Hugging Face cache, a folder the user added),
        /// run inside the app from where it is; the id is the model folder's absolute path.
        case folder
        /// Reached over an HTTP API (see `ModelAPI`): hosted services with the user's key, or a server on this Mac.
        case openAI = "openai"
        case anthropic
        case gemini
        case openRouter = "openrouter"
        case groq
        case deepSeek = "deepseek"
        case ollama
        case llamaCpp = "llamacpp"
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

extension LocalModelChoice.Server {
    /// Runs inside Bilge rather than behind another program's server.
    public var isInApp: Bool { self == .builtIn || self == .custom || self == .folder }

    public var api: ModelAPI? { ModelAPI(server: self) }
}

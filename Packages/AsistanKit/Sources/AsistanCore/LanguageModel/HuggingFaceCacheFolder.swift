import Foundation

/// The Hugging Face hub cache, where mlx-lm, vMLX and other tools keep the models they download.
/// Layout: `<hub>/models--<org>--<name>/snapshots/<revision>/`, with refs/main naming the current revision.
public enum HuggingFaceCacheFolder {
    private static let repoPrefix = "models--"

    /// Follows the same variables as the huggingface_hub library, in the same order.
    public static func hubRoot(environment: [String: String], userHome: URL) -> URL {
        if let hub = absolute(environment["HF_HUB_CACHE"]) { return hub }
        if let home = absolute(environment["HF_HOME"]) { return home.appending(path: "hub", directoryHint: .isDirectory) }
        let cache = absolute(environment["XDG_CACHE_HOME"]) ?? userHome.appending(path: ".cache", directoryHint: .isDirectory)
        return cache.appending(path: "huggingface/hub", directoryHint: .isDirectory)
    }

    /// "models--mlx-community--Qwen3-8B-4bit" → "mlx-community/Qwen3-8B-4bit"; nil for datasets, spaces and other entries.
    public static func repoID(cacheFolderName name: String) -> String? {
        guard name.hasPrefix(repoPrefix) else { return nil }
        let parts = name.dropFirst(repoPrefix.count).components(separatedBy: "--")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return parts.joined(separator: "/")
    }

    private static func absolute(_ path: String?) -> URL? {
        guard let path, path.hasPrefix("/") else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}

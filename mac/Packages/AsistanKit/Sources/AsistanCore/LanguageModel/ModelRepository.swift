import Foundation

/// A file in a Hugging Face model repository, as listed by `/api/models/<id>/tree/<revision>`.
public struct RepositoryFile: Decodable, Sendable, Equatable {
    public struct LargeFile: Decodable, Sendable, Equatable {
        /// SHA-256 of the content, hex.
        public let oid: String
        public let size: Int64
    }

    public let type: String
    public let path: String
    public let size: Int64
    public let lfs: LargeFile?

    public init(type: String = "file", path: String, size: Int64, lfs: LargeFile? = nil) {
        self.type = type
        self.path = path
        self.size = size
        self.lfs = lfs
    }

    /// Weights and anything over a few megabytes are stored with LFS, which publishes their SHA-256.
    public var expectedSHA256: String? { lfs?.oid.lowercased() }
}

public enum ModelRepository {
    private static let neededExtensions: Set<String> = ["safetensors", "json", "jinja", "model", "txt", "tiktoken"]
    private static let skippedNames: Set<String> = ["README.md", ".gitattributes"]
    private static var revisionPattern: Regex<Substring> { /^[0-9a-f]{40}$/ }
    private static var namePattern: Regex<Substring> { /^[A-Za-z0-9][A-Za-z0-9._-]*$/ }

    /// The files needed to load the model: weights, configuration, tokenizer and chat template.
    /// Paths come from the network, so anything that could leave the model's folder is dropped.
    public static func neededFiles(_ files: [RepositoryFile]) -> [RepositoryFile] {
        files.filter { file in
            guard file.type == "file", file.size >= 0, isSafeRelativePath(file.path) else { return false }
            let name = (file.path as NSString).lastPathComponent
            guard !skippedNames.contains(name) else { return false }
            return neededExtensions.contains((name as NSString).pathExtension.lowercased())
        }
    }

    /// A relative path inside the model folder: no "..", no absolute path, no hidden parts.
    public static func isSafeRelativePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, !path.hasPrefix("/") else { return false }
        return parts.allSatisfy { part in !part.isEmpty && !part.hasPrefix(".") && part.wholeMatch(of: namePattern) != nil }
    }

    /// "owner/name", each part a plain name.
    public static func isValidID(_ id: String) -> Bool {
        let parts = id.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { $0.wholeMatch(of: namePattern) != nil && !$0.hasPrefix(".") }
    }

    /// A full commit hash, so a download is pinned to exactly what was reviewed.
    public static func isPinnedRevision(_ revision: String) -> Bool {
        revision.wholeMatch(of: revisionPattern) != nil
    }

    /// nil when a size is negative or the sum overflows; the listing comes from the network.
    public static func totalSize(_ files: [RepositoryFile]) -> Int64? {
        var total: Int64 = 0
        for file in files {
            guard file.size >= 0 else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(file.size)
            if overflow { return nil }
            total = sum
        }
        return total
    }
}

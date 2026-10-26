import Foundation

/// Checks a model folder chosen in settings against the folders Bilge searches, so a stored path can
/// only ever load a model from one of them.
public enum ModelSearchRoots {
    public static func contains(_ folder: String, roots: [String]) -> Bool {
        guard folder.hasPrefix("/"), !folder.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) else { return false }
        return roots.contains { root in
            let prefix = root.hasSuffix("/") ? root : root + "/"
            return folder.hasPrefix(prefix) && folder.count > prefix.count
        }
    }
}

import Foundation

/// Where LM Studio keeps the models it downloaded, so Bilge can run its MLX models in place instead of
/// downloading them again.
public enum LMStudioModelsFolder {
    /// LM Studio writes the path of its home folder here, in the user's home folder.
    public static let homePointerFile = ".lmstudio-home-pointer"
    public static let settingsFile = "settings.json"
    private static let defaultHome = ".lmstudio"
    private static let defaultModels = "models"

    /// `pointer` is the contents of the home pointer file, if there is one.
    public static func home(userHome: URL, pointer: String?) -> URL {
        absoluteFolder(pointer) ?? userHome.appending(path: defaultHome, directoryHint: .isDirectory)
    }

    /// `settings` is LM Studio's settings.json, which names the models folder when the user moved it.
    public static func modelsRoot(home: URL, settings: Data?) -> URL {
        let object = settings.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return absoluteFolder(object?["downloadsFolder"] as? String)
            ?? home.appending(path: defaultModels, directoryHint: .isDirectory)
    }

    /// "<publisher>/<model>", the layout LM Studio downloads into. Anything else could point outside the folder.
    public static func isValidID(_ id: String) -> Bool {
        let parts = id.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return parts.count == 2 && parts.allSatisfy(MLXModelFolder.isValidName)
    }

    private static func absoluteFolder(_ path: String?) -> URL? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), path.hasPrefix("/") else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}

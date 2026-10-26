import Foundation

/// Whether a folder the user put in Bilge's models folder holds a loadable MLX language model.
public enum MLXModelFolder {
    public enum Status: Sendable, Hashable {
        case ready(modelType: String)
        case missing(String)
    }

    private static let tokenizerFiles: Set<String> = ["tokenizer.json", "tokenizer.model"]
    /// JANG models (made for vMLX) name their per-layer quantization after the original checkpoint's layers,
    /// which MLX Swift can't match: loading fails on the first layer with its own bit width.
    private static let jangConfig = "jang_config.json"

    /// `fileNames` are the folder's top-level entries; `config` is the contents of its config.json.
    public static func inspect(fileNames: [String], config: Data?) -> Status {
        guard let config else { return .missing("config.json yok") }
        guard fileNames.contains(where: { $0.hasSuffix(".safetensors") }) else { return .missing(".safetensors dosyası yok") }
        guard fileNames.contains(where: tokenizerFiles.contains) else { return .missing("tokenizer dosyası yok") }
        guard !fileNames.contains(jangConfig) else { return .missing("JANG biçimi yalnızca vMLX'te çalışır") }
        guard let object = try? JSONSerialization.jsonObject(with: config) as? [String: Any],
              let modelType = object["model_type"] as? String, !modelType.isEmpty
        else { return .missing("config.json'da model_type yok") }
        return .ready(modelType: modelType)
    }

    /// A single plain folder name, so a stored choice cannot point outside the models folder.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains(":") && name != ".."
    }
}

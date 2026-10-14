/// A conversation model Bilge can download and run itself, pinned to a reviewed commit.
public struct DownloadableModel: Sendable, Hashable, Identifiable {
    /// Hugging Face repository, "owner/name".
    public let id: String
    public let revision: String
    public let name: String
    public let summary: String
    public let downloadBytes: Int64
    /// Total memory a Mac needs for the model to run alongside the rest of Bilge and other apps.
    public let minimumMemoryGB: Int
    public let license: String
    /// Sent to the chat template; Qwen 3 thinks for seconds before answering unless this is off.
    public let disablesThinking: Bool

    public func fits(physicalMemoryBytes: UInt64) -> Bool {
        physicalMemoryBytes >= UInt64(minimumMemoryGB) << 30
    }
}

public enum ModelCatalog {
    /// Smallest first. Sizes are the files Bilge downloads at the pinned revision.
    public static let models: [DownloadableModel] = [
        DownloadableModel(
            id: "mlx-community/gemma-4-12B-it-4bit", revision: "73bcf09092aa277861d5a191b989b666f7f32e8f",
            name: "Gemma 4 12B", summary: "Orta boy. Kısa ve düzgün Türkçe cevaplar; genel bilgide Apple modelinden belirgin biçimde iyi.",
            downloadBytes: 6_773_371_194, minimumMemoryGB: 24, license: "Apache 2.0", disablesThinking: false),
        DownloadableModel(
            id: "mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit", revision: "e9675aa3ca5f900ccef55267914466d55ab325fa",
            name: "Qwen3 30B A3B", summary: "Büyük ama hızlı: her kelimede modelin yalnızca küçük bir kısmı çalışır. Bilgi soruları ve çok adımlı işler için.",
            downloadBytes: 17_197_084_801, minimumMemoryGB: 32, license: "Apache 2.0", disablesThinking: false),
        DownloadableModel(
            id: "mlx-community/Qwen3.6-35B-A3B-4bit", revision: "38740b847e4cb78f352aba30aa41c76e08e6eb46",
            name: "Qwen3.6 35B A3B", summary: "En bilgili seçenek; büyük belleği olan Mac'ler için.",
            downloadBytes: 20_429_166_969, minimumMemoryGB: 36, license: "Apache 2.0", disablesThinking: true),
    ]

    public static func model(id: String) -> DownloadableModel? {
        models.first { $0.id == id }
    }
}

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

    public func fits(physicalMemoryBytes: UInt64) -> Bool {
        physicalMemoryBytes >= UInt64(minimumMemoryGB) << 30
    }
}

public enum ModelCatalog {
    /// Smallest first. Sizes are the files Bilge downloads at the pinned revision.
    public static let models: [DownloadableModel] = [
        DownloadableModel(
            id: "mlx-community/Qwen3.6-27B-4bit", revision: "c000ac2c2057d94be3fa931000c31723aac53282",
            name: "Qwen3.6 27B", summary: "Qwen 3.8'in bir önceki sürümü.",
            downloadBytes: 16_081_487_798, minimumMemoryGB: 32, license: "Apache 2.0"),
        DownloadableModel(
            id: "mlx-community/Qwen3.8-27B-4bit", revision: "10c35caafbb80f7dc6a7a432cdd11af10a6d4818",
            name: "Qwen3.8 27B", summary: "Türkçe genel bilgide güçlü, cevabı hızlı üretir. Testlerimizde en iyi sonuç veren model ailesi.",
            downloadBytes: 16_081_488_731, minimumMemoryGB: 32, license: "Apache 2.0"),
        DownloadableModel(
            id: "mlx-community/gemma-4-31b-it-4bit", revision: "696d436c404745a59f30e4939a658162b0a9e57f",
            name: "Gemma 4 31B", summary: "Google'ın büyük Gemma 4 modeli; Türkçe genel bilgide güçlü, ilk kelimeye çabuk başlar.",
            downloadBytes: 18_444_419_448, minimumMemoryGB: 32, license: "Apache 2.0"),
    ]

    public static func model(id: String) -> DownloadableModel? {
        models.first { $0.id == id }
    }
}

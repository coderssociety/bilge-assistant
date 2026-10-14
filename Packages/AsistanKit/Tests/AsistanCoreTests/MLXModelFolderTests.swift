import Foundation
import Testing
@testable import AsistanCore

@Suite("MLXModelFolder")
struct MLXModelFolderTests {
    private let config = Data(#"{"model_type": "qwen3_5", "hidden_size": 5120}"#.utf8)
    private let files = ["config.json", "model-00001-of-00004.safetensors", "tokenizer.json", "chat_template.jinja"]

    @Test("a complete folder is ready, with its model type")
    func ready() {
        #expect(MLXModelFolder.inspect(fileNames: files, config: config) == .ready(modelType: "qwen3_5"))
        #expect(MLXModelFolder.inspect(fileNames: ["config.json", "model.safetensors", "tokenizer.model"], config: config)
            == .ready(modelType: "qwen3_5"))
    }

    @Test("says what is missing")
    func missing() {
        #expect(MLXModelFolder.inspect(fileNames: files, config: nil) == .missing("config.json yok"))
        #expect(MLXModelFolder.inspect(fileNames: ["config.json", "tokenizer.json", "model.gguf"], config: config)
            == .missing(".safetensors dosyası yok"))
        #expect(MLXModelFolder.inspect(fileNames: ["config.json", "model.safetensors"], config: config)
            == .missing("tokenizer dosyası yok"))
        #expect(MLXModelFolder.inspect(fileNames: files, config: Data("{}".utf8)) == .missing("config.json'da model_type yok"))
        #expect(MLXModelFolder.inspect(fileNames: files, config: Data("not json".utf8)) == .missing("config.json'da model_type yok"))
    }

    @Test("folder names stay inside the models folder", arguments: [
        ("Qwen3.8-27B-4bit", true), ("Benim Modelim", true), ("", false), ("..", false), (".gizli", false),
        ("a/b", false), ("../x", false), ("a:b", false),
    ])
    func names(name: String, isValid: Bool) {
        #expect(MLXModelFolder.isValidName(name) == isValid)
    }
}

import Testing
@testable import AsistanCore

@Suite("LocalModelChoice")
struct LocalModelChoiceTests {
    @Test("round-trips through its storage key", arguments: [
        LocalModelChoice(server: .lmStudio, modelID: "qwen3.8-27b-uncensored-mlx"),
        LocalModelChoice(server: .vmlx, modelID: "dealignai/Gemma-4-31B-JANG_4M-Uncensored"),
        LocalModelChoice(server: .builtIn, modelID: "mlx-community/Qwen3-4B-Instruct-2507-4bit"),
    ])
    func roundTrip(choice: LocalModelChoice) {
        #expect(LocalModelChoice(storageKey: choice.storageKey) == choice)
    }

    @Test("a bare id saved by the previous version means LM Studio")
    func legacyValue() {
        #expect(LocalModelChoice(storageKey: "qwen3.8-27b-uncensored-mlx")
            == LocalModelChoice(server: .lmStudio, modelID: "qwen3.8-27b-uncensored-mlx"))
    }

    @Test("rejects empty or unknown values", arguments: ["", "vmlx:", "ollama:llama3", ":x"])
    func invalid(key: String) {
        #expect(LocalModelChoice(storageKey: key) == nil)
    }
}

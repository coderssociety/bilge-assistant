import Foundation
import Testing
@testable import AsistanCore

@Suite("LMStudioModelsFolder")
struct LMStudioModelsFolderTests {
    private let userHome = URL(filePath: "/Users/ayse", directoryHint: .isDirectory)

    @Test("defaults to ~/.lmstudio/models")
    func defaults() {
        let home = LMStudioModelsFolder.home(userHome: userHome, pointer: nil)
        #expect(LMStudioModelsFolder.modelsRoot(home: home, settings: nil).path() == "/Users/ayse/.lmstudio/models/")
    }

    @Test("follows the home pointer and a moved models folder")
    func moved() {
        let home = LMStudioModelsFolder.home(userHome: userHome, pointer: "/Volumes/SSD/lmstudio\n")
        #expect(home.path() == "/Volumes/SSD/lmstudio/")
        let settings = Data(#"{"downloadsFolder": "/Volumes/SSD/models"}"#.utf8)
        #expect(LMStudioModelsFolder.modelsRoot(home: home, settings: settings).path() == "/Volumes/SSD/models/")
    }

    @Test("ignores relative or unreadable paths", arguments: ["", "models", "~/x"])
    func relative(path: String) {
        let home = LMStudioModelsFolder.home(userHome: userHome, pointer: path)
        #expect(home.path() == "/Users/ayse/.lmstudio/")
        let settings = Data(#"{"downloadsFolder": "\#(path)"}"#.utf8)
        #expect(LMStudioModelsFolder.modelsRoot(home: home, settings: settings).path() == "/Users/ayse/.lmstudio/models/")
        #expect(LMStudioModelsFolder.modelsRoot(home: home, settings: Data("not json".utf8)).path() == "/Users/ayse/.lmstudio/models/")
    }

    @Test("accepts publisher/model ids", arguments: ["orcarouter/Qwen3.8-27B-Uncensored-MLX", "mlx-community/gemma-4-31b-it-4bit"])
    func validID(id: String) {
        #expect(LMStudioModelsFolder.isValidID(id))
    }

    @Test("rejects ids that could leave the folder", arguments: ["", "model", "a/b/c", "../x", "a/..", "a/.hidden", "/a/b", "a/", "a:b/c"])
    func invalidID(id: String) {
        #expect(!LMStudioModelsFolder.isValidID(id))
    }
}

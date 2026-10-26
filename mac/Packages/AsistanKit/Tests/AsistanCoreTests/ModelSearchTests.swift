import Foundation
import Testing
@testable import AsistanCore

@Suite("Model search folders")
struct ModelSearchTests {
    private let userHome = URL(filePath: "/Users/ayse", directoryHint: .isDirectory)

    @Test("the Hugging Face cache follows HF_HUB_CACHE, HF_HOME and XDG_CACHE_HOME in that order")
    func hubRoot() {
        let root = { (environment: [String: String]) in
            HuggingFaceCacheFolder.hubRoot(environment: environment, userHome: userHome).path()
        }
        #expect(root([:]) == "/Users/ayse/.cache/huggingface/hub/")
        #expect(root(["XDG_CACHE_HOME": "/tmp/cache"]) == "/tmp/cache/huggingface/hub/")
        #expect(root(["HF_HOME": "/Volumes/SSD/hf", "XDG_CACHE_HOME": "/tmp/cache"]) == "/Volumes/SSD/hf/hub/")
        #expect(root(["HF_HUB_CACHE": "/Volumes/SSD/hub", "HF_HOME": "/Volumes/SSD/hf"]) == "/Volumes/SSD/hub/")
        #expect(root(["HF_HOME": "relative"]) == "/Users/ayse/.cache/huggingface/hub/")
    }

    @Test("cache folder names map to repository ids", arguments: [
        ("models--mlx-community--Qwen3-8B-4bit", "mlx-community/Qwen3-8B-4bit"),
        ("models--Systran--faster-whisper-base", "Systran/faster-whisper-base"),
    ])
    func repoID(name: String, id: String) {
        #expect(HuggingFaceCacheFolder.repoID(cacheFolderName: name) == id)
    }

    @Test("other cache entries have no model id", arguments: ["datasets--a--b", "CACHEDIR.TAG", "models--only", "models----x", ".locks"])
    func notRepo(name: String) {
        #expect(HuggingFaceCacheFolder.repoID(cacheFolderName: name) == nil)
    }

    @Test("a stored path must sit inside a searched folder")
    func inside() {
        let roots = ["/Users/ayse/.lmstudio/models", "/Volumes/SSD/AI/"]
        #expect(ModelSearchRoots.contains("/Users/ayse/.lmstudio/models/org/model", roots: roots))
        #expect(ModelSearchRoots.contains("/Volumes/SSD/AI/qwen", roots: roots))
        #expect(!ModelSearchRoots.contains("/Users/ayse/.lmstudio/models", roots: roots))
        #expect(!ModelSearchRoots.contains("/Users/ayse/.lmstudio/models-old/x", roots: roots))
        #expect(!ModelSearchRoots.contains("/Users/ayse/.lmstudio/models/../../secret", roots: roots))
        #expect(!ModelSearchRoots.contains("relative/models/x", roots: roots))
        #expect(!ModelSearchRoots.contains("/etc/x", roots: []))
    }
}

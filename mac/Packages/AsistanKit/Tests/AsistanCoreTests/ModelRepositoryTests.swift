import Foundation
import Testing
@testable import AsistanCore

@Suite("ModelRepository")
struct ModelRepositoryTests {
    @Test("keeps weights, configuration, tokenizer and template; drops docs and folders")
    func neededFiles() {
        let files = [
            RepositoryFile(path: "model-00001-of-00002.safetensors", size: 5_000, lfs: .init(oid: "AB", size: 5_000)),
            RepositoryFile(path: "model.safetensors.index.json", size: 30),
            RepositoryFile(path: "config.json", size: 10),
            RepositoryFile(path: "tokenizer.json", size: 20),
            RepositoryFile(path: "tokenizer.model", size: 20),
            RepositoryFile(path: "chat_template.jinja", size: 5),
            RepositoryFile(path: "merges.txt", size: 5),
            RepositoryFile(path: "README.md", size: 5),
            RepositoryFile(path: ".gitattributes", size: 5),
            RepositoryFile(path: "image.png", size: 5),
            RepositoryFile(type: "directory", path: "extra", size: 0),
        ]
        #expect(ModelRepository.neededFiles(files).map(\.path) == [
            "model-00001-of-00002.safetensors", "model.safetensors.index.json", "config.json", "tokenizer.json",
            "tokenizer.model", "chat_template.jinja", "merges.txt",
        ])
        #expect(files[0].expectedSHA256 == "ab")
    }

    @Test("rejects paths that could leave the model folder", arguments: [
        "../config.json", "/etc/config.json", "a/../../config.json", ".hidden/config.json", "a//config.json", "",
        "con fig.json",
    ])
    func unsafePaths(path: String) {
        #expect(!ModelRepository.isSafeRelativePath(path))
        #expect(ModelRepository.neededFiles([RepositoryFile(path: path, size: 1)]).isEmpty)
    }

    @Test("accepts plain nested paths")
    func nestedPath() {
        #expect(ModelRepository.isSafeRelativePath("tokenizer/tokenizer.json"))
    }

    @Test("repository ids are owner/name", arguments: [
        ("mlx-community/Qwen3-4B-Instruct-2507-4bit", true), ("a/b/c", false), ("../x", false),
        ("owner/.git", false), ("owner", false), ("owner/na me", false),
    ])
    func ids(id: String, isValid: Bool) {
        #expect(ModelRepository.isValidID(id) == isValid)
    }

    @Test("revisions must be full commit hashes")
    func revisions() {
        #expect(ModelRepository.isPinnedRevision(String(repeating: "a1", count: 20)))
        #expect(!ModelRepository.isPinnedRevision("main"))
        #expect(!ModelRepository.isPinnedRevision("A1B2"))
    }

    @Test("rejects negative sizes and totals that overflow")
    func hostileSizes() {
        #expect(ModelRepository.neededFiles([RepositoryFile(path: "config.json", size: -1)]).isEmpty)
        #expect(ModelRepository.totalSize([RepositoryFile(path: "a.json", size: -5)]) == nil)
        #expect(ModelRepository.totalSize([RepositoryFile(path: "a.json", size: .max), RepositoryFile(path: "b.json", size: 1)]) == nil)
        #expect(ModelRepository.totalSize([]) == 0)
    }

    @Test("decodes the Hugging Face tree listing")
    func decodes() throws {
        let json = #"[{"type":"file","oid":"x","size":42,"path":"config.json"},"#
            + #"{"type":"file","oid":"y","size":7,"path":"model.safetensors","lfs":{"oid":"abc","size":7,"pointerSize":134}}]"#
        let files = try JSONDecoder().decode([RepositoryFile].self, from: Data(json.utf8))
        #expect(files.map(\.path) == ["config.json", "model.safetensors"])
        #expect(files[1].expectedSHA256 == "abc")
        #expect(ModelRepository.totalSize(files) == 49)
    }
}

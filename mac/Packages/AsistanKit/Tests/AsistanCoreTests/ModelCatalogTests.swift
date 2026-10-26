import Testing
@testable import AsistanCore

@Suite("ModelCatalog")
struct ModelCatalogTests {
    @Test("every model is pinned to a commit and safe to store", arguments: ModelCatalog.models)
    func pinned(model: DownloadableModel) {
        #expect(ModelRepository.isValidID(model.id))
        #expect(ModelRepository.isPinnedRevision(model.revision))
        #expect(model.downloadBytes > 0)
        #expect(UInt64(model.downloadBytes) < UInt64(model.minimumMemoryGB) << 30)
    }

    @Test("ids are unique and models go from small to large")
    func ordering() {
        let models = ModelCatalog.models
        #expect(Set(models.map(\.id)).count == models.count)
        #expect(models.map(\.downloadBytes) == models.map(\.downloadBytes).sorted())
    }

    @Test("memory check")
    func fits() throws {
        let small = try #require(ModelCatalog.models.first)
        let required = UInt64(small.minimumMemoryGB) << 30
        #expect(small.fits(physicalMemoryBytes: required))
        #expect(!small.fits(physicalMemoryBytes: required - 1))
        #expect(ModelCatalog.model(id: small.id) == small)
        #expect(ModelCatalog.model(id: "nobody/none") == nil)
    }
}

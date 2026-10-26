import Foundation
import Testing
@testable import AsistanCore

@Suite("ScreenContext")
struct ScreenContextTests {
    private let pdf = URL(filePath: "/Users/u/Downloads/rapor.pdf")
    private let page = URL(string: "https://ntv.com.tr/haber")!

    @Test("requests that point at something on screen", arguments: [
        ("Bunu özetle", ContextIntent(action: .summarize, wanted: nil)),
        ("Seçili metni İngilizceye çevir", ContextIntent(action: .translate, wanted: .text)),
        ("Bu sayfayı özetle", ContextIntent(action: .summarize, wanted: .page)),
        ("Şu dosyayı aç", ContextIntent(action: .open, wanted: .file)),
        ("Bu belgede ne yazıyor", ContextIntent(action: .read, wanted: .document)),
        ("Bunu açıklar mısın", ContextIntent(action: .explain, wanted: nil)),
        ("Açık PDF'i özetle", ContextIntent(action: .summarize, wanted: .document)),
    ])
    func intents(command: String, expected: ContextIntent) {
        #expect(ContextIntent.parse(command) == expected)
    }

    @Test("commands that do not point at the screen", arguments: [
        "Safari'yi aç", "Son indirdiğim PDF'i özetle", "Bugün hava nasıl", "Bu akşam ne var", "Ahmet'e mesaj at",
        "Bu şarkıyı değiştir",
    ])
    func notIntents(command: String) {
        #expect(ContextIntent.parse(command) == nil)
    }

    @Test("what 'bu' refers to, by what is on screen")
    func resolution() {
        let everything = ScreenContext(selectedText: "Seçili paragraf", selectedFiles: [pdf], pageURL: page, pageTitle: "Haber",
                                       documentURL: pdf)
        #expect(ContextResolver.resolve(nil, in: everything) == .text("Seçili paragraf"))
        #expect(ContextResolver.resolve(.page, in: everything) == .page(page, title: "Haber"))
        #expect(ContextResolver.resolve(.file, in: everything) == .files([pdf]))
        let browsing = ScreenContext(selectedText: nil, selectedFiles: [], pageURL: page, pageTitle: nil, documentURL: nil)
        #expect(ContextResolver.resolve(nil, in: browsing) == .page(page, title: nil))
        #expect(ContextResolver.resolve(.text, in: browsing) == nil)
        let reading = ScreenContext(selectedText: "  ", selectedFiles: [], pageURL: nil, pageTitle: nil, documentURL: pdf)
        #expect(ContextResolver.resolve(nil, in: reading) == .document(pdf))
        #expect(ContextResolver.resolve(.file, in: reading) == .files([pdf]))
        #expect(ContextResolver.resolve(nil, in: ScreenContext()) == nil)
    }

    @Test("a message body that only points at the screen", arguments: [
        ("", true), ("bunu", true), ("Şunu", true), ("bu linki", true), ("seçili metni", true), ("bu dosyayı", true),
        ("Yarın gelemeyeceğim", false), ("bunu yarın konuşalım", false),
    ])
    func pointingBody(text: String, pointing: Bool) {
        #expect(ContextIntent.onlyPoints(text) == pointing)
    }

    @Test("commands worth reading the screen for")
    func pointing() {
        #expect(ContextIntent.points("Bunu Ahmet'e gönder"))
        #expect(ContextIntent.points("Şu dosyayı Zeynep'e mail at"))
        #expect(!ContextIntent.points("Bu akşam ne yapsak"))
        #expect(!ContextIntent.points("Ahmet'e geç kalacağımı yaz"))
        #expect(ContextIntent.wantedKind(in: "bu linki") == .page)
        #expect(ContextIntent.wantedKind(in: "bunu") == nil)
    }
}

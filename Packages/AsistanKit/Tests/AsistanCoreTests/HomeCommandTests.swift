import Foundation
import Testing
@testable import AsistanCore

@Suite("HomeCommand")
struct HomeCommandTests {
    @Test("Turkish home commands name a device or room", arguments: [
        "salonun ışığını aç", "klimayı 22 dereceye ayarla", "kapı kilitli mi", "ışıkları kapat",
        "yatak odasındaki lambayı söndür", "mutfağın perdelerini kapat", "garaj kapısını aç", "termostatı 21 yap", "prizi kapat",
    ])
    func turkishDevices(said: String) {
        #expect(HomeCommand.namesHomeDevice(said, language: .turkish))
    }

    @Test("commands for this Mac or anything else are not home commands", arguments: [
        "ekranın ışığını kıs", "bilgisayarı kilitle", "ekranı kilitle", "klavye ışığını aç", "hava nasıl",
        "yarın 7'ye alarm kur", "sesi aç", "haberleri oku", "salı günü toplantım var mı",
    ])
    func notHome(said: String) {
        #expect(!HomeCommand.namesHomeDevice(said, language: .turkish))
    }

    @Test("English home commands")
    func english() {
        #expect(HomeCommand.namesHomeDevice("turn on the living room lights", language: .english))
        #expect(HomeCommand.namesHomeDevice("set the thermostat to 21", language: .english))
        #expect(HomeCommand.namesHomeDevice("is the front door locked", language: .english))
        #expect(!HomeCommand.namesHomeDevice("lock the screen", language: .english))
        #expect(!HomeCommand.namesHomeDevice("what's the weather", language: .english))
    }

    @Test("only changing a lock, the garage door or the alarm guards the house")
    func guards() {
        #expect(HomeCommand.guardsTheHouse("kapıyı kilitle", language: .turkish))
        #expect(HomeCommand.guardsTheHouse("kapının kilidini aç", language: .turkish))
        #expect(HomeCommand.guardsTheHouse("garajı aç", language: .turkish))
        #expect(HomeCommand.guardsTheHouse("garaj kapısını aç", language: .turkish))
        #expect(HomeCommand.guardsTheHouse("ev alarmını kapat", language: .turkish))
        #expect(!HomeCommand.guardsTheHouse("kapı kilitli mi", language: .turkish))
        #expect(!HomeCommand.guardsTheHouse("salonun ışığını aç", language: .turkish))
        #expect(HomeCommand.guardsTheHouse("unlock the front door", language: .english))
        #expect(!HomeCommand.guardsTheHouse("is the front door locked", language: .english))
    }

    @Test("a polite request with a question mark still guards the house", arguments: [
        ("kapının kilidini açar mısın?", AssistantLanguage.turkish), ("garaj kapısını açar mısın?", .turkish),
        ("kapıyı kilitler misin?", .turkish), ("alarmı kapatabilir misin?", .turkish), ("kapıyı açar mı?", .turkish),
        ("kapıyı aç ne olur", .turkish), ("kapıyı açsana", .turkish), ("kapıyı açayım mı?", .turkish),
        ("can you unlock the front door?", .english), ("could you open the garage?", .english),
        ("open the front door", .english), ("please open the gate?", .english),
    ])
    func politeRequestGuards(said: String, language: AssistantLanguage) {
        #expect(HomeCommand.guardsTheHouse(said, language: language))
    }

    @Test("asking about a lock, the garage or the alarm needs no yes", arguments: [
        ("kapı kilitli mi?", AssistantLanguage.turkish), ("garaj kapısı açık mı", .turkish), ("alarm kurulu mu?", .turkish),
        ("ön kapı kilitli midir", .turkish), ("alarm ne durumda", .turkish), ("garajda alarm var mı", .turkish),
        ("is the front door locked?", .english), ("is the garage door open", .english), ("what's the alarm status", .english),
    ])
    func statusQuestion(said: String, language: AssistantLanguage) {
        #expect(!HomeCommand.guardsTheHouse(said, language: language))
    }

    @Test("the address is a plain http(s) address")
    func address() {
        #expect(HomeAssistantAPI.baseAddress("http://homeassistant.local:8123/")?.absoluteString == "http://homeassistant.local:8123")
        #expect(HomeAssistantAPI.baseAddress(" https://ev.example.org/ha ")?.absoluteString == "https://ev.example.org/ha")
        #expect(HomeAssistantAPI.baseAddress("http://192.168.1.20:8123")?.absoluteString == "http://192.168.1.20:8123")
        for bad in ["homeassistant.local:8123", "ftp://ev", "http://user:pass@ev:8123", "http://ev:8123/?x=1", "http://ev:port", ""] {
            #expect(HomeAssistantAPI.baseAddress(bad) == nil, "\(bad)")
        }
    }

    @Test("the conversation request carries the text, the language and the token")
    func conversationRequest() throws {
        let base = try #require(HomeAssistantAPI.baseAddress("http://homeassistant.local:8123"))
        let request = HomeAssistantAPI.conversationRequest("salonun ışığını aç", language: .turkish, base: base, token: "abc.def")
        let text = String(decoding: request, as: UTF8.self)
        let parts = text.components(separatedBy: "\r\n\r\n")
        let head = parts[0].components(separatedBy: "\r\n")
        #expect(head[0] == "POST /api/conversation/process HTTP/1.1")
        #expect(head.contains("Host: homeassistant.local:8123"))
        #expect(head.contains("Authorization: Bearer abc.def"))
        #expect(head.contains("Content-Type: application/json"))
        let body = Data(parts[1].utf8)
        #expect(head.contains("Content-Length: \(body.count)"))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["text": "salonun ışığını aç", "language": "tr"])
        let english = HomeAssistantAPI.conversationRequest("lights on", language: .english, base: base, token: "t")
        #expect(String(decoding: english, as: UTF8.self).hasSuffix(#"{"language":"en","text":"lights on"}"#))
    }

    @Test("the status request keeps an address path and a token with a line break is never sent")
    func statusRequest() throws {
        let base = try #require(HomeAssistantAPI.baseAddress("https://ev.example.org/ha/"))
        let text = String(decoding: HomeAssistantAPI.statusRequest(base: base, token: "abc"), as: UTF8.self)
        #expect(text.hasPrefix("GET /ha/api/ HTTP/1.1\r\n"))
        #expect(text.contains("Authorization: Bearer abc\r\n"))
        let injected = String(decoding: HomeAssistantAPI.statusRequest(base: base, token: "abc\r\nX-Evil: 1"), as: UTF8.self)
        #expect(!injected.contains("X-Evil"))
    }

    @Test("the spoken reply is read from the conversation response")
    func spokenReply() throws {
        #expect(try HomeAssistantAPI.spokenReply(from: HomeAssistantFixtures.actionDone) == "Salon ışığı açıldı")
        #expect(try HomeAssistantAPI.spokenReply(from: HomeAssistantFixtures.noMatch) == "Sorry, I couldn't understand that")
        #expect(try HomeAssistantAPI.spokenReply(from: HomeAssistantFixtures.silent) == nil)
        #expect(throws: HomeAssistantAPI.ResponseError.unexpected) { try HomeAssistantAPI.spokenReply(from: HomeAssistantFixtures.status) }
        #expect(throws: HomeAssistantAPI.ResponseError.unexpected) { try HomeAssistantAPI.spokenReply(from: Data("[1,2]".utf8)) }
        #expect(throws: HomeAssistantAPI.ResponseError.unexpected) { try HomeAssistantAPI.spokenReply(from: Data("<html>".utf8)) }
    }
}

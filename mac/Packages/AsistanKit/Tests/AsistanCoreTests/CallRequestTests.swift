import Testing
@testable import AsistanCore

@Suite("Call requests")
struct CallRequestTests {
    @Test("a person and 'ara' is a call", arguments: [
        ("annemi ara", "annem", CallRequest.Mode.phone, true),
        ("babamı arar mısın", "babam", .phone, true),
        ("Ahmet'i FaceTime'la ara", "Ahmet", .faceTimeAudio, true),
        ("Ayşe'yi sesli ara", "Ayşe", .faceTimeAudio, true),
        ("eşimi görüntülü ara", "eşim", .faceTimeVideo, true),
        ("oğlumu telefonla ara", "oğlum", .phone, true),
        ("Ahmet Yılmaz'ı ara", "Ahmet Yılmaz", .phone, false),
        ("lütfen Burcu'yu ara", "Burcu", .phone, false),
        ("anneme telefon et", "annem", .phone, true),
        ("Can'a telefon açar mısın", "Can", .phone, true),
        ("ahmeti facetime ile ara", "ahmeti", .faceTimeAudio, true),
    ])
    func turkishCall(command: String, name: String, mode: CallRequest.Mode, certain: Bool) {
        #expect(CallRequest.parse(command) == CallRequest(name: name, mode: mode, isCertain: certain))
    }

    @Test("'ara' as a search is not a call", arguments: [
        "Atatürk'ü internette ara", "Kadıköy'ü haritada ara", "en yakın eczaneyi ara", "kediyi ara",
        "Google'da Ahmet'i ara", "İstanbul'daki otelleri ara", "bir taksi ara", "Ahmet'in numarasını bul",
        "Spotify'da Tarkan'ı ara", "Mail'de Ahmet'i ara", "Deezer'da Sezen Aksu'yu ara", "Safari'de Ahmet'i ara",
        "Notlar'da Ayşe'yi ara", "müzikte Tarkan'ı ara",
    ])
    func search(command: String) {
        #expect(CallRequest.parse(command) == nil)
    }

    @Test("English calls", arguments: [
        ("call mom", "mom", CallRequest.Mode.phone), ("call my dad please", "dad", .phone),
        ("FaceTime Ahmet", "Ahmet", .faceTimeAudio), ("video call Ayşe", "Ayşe", .faceTimeVideo),
        ("call Ahmet Yılmaz on FaceTime", "Ahmet Yılmaz", .faceTimeAudio),
    ])
    func englishCall(command: String, name: String, mode: CallRequest.Mode) {
        #expect(CallRequest.parse(command, language: .english) == CallRequest(name: name, mode: mode, isCertain: true))
    }

    @Test("English phrases that are not calls", arguments: ["call me a taxi", "what do you call this", "phone number of Ahmet"])
    func englishNotCall(command: String) {
        #expect(CallRequest.parse(command, language: .english) == nil)
    }

    @Test("a phone call needs a number; FaceTime also takes an e-mail address")
    func destination() {
        let phone = CallRequest.destination(for: .phone, phones: ["0532 123 45 67"], emails: ["a@b.com"])
        #expect(phone?.address == "0532 123 45 67")
        #expect(phone?.url.absoluteString == "tel:+905321234567")
        #expect(CallRequest.destination(for: .phone, phones: [], emails: ["a@b.com"]) == nil)
        let audio = CallRequest.destination(for: .faceTimeAudio, phones: [], emails: ["a@b.com"])
        #expect(audio?.url.absoluteString == "facetime-audio://a@b.com")
        let video = CallRequest.destination(for: .faceTimeVideo, phones: ["+44 20 7946 0958"], emails: [])
        #expect(video?.url.absoluteString == "facetime://+442079460958")
    }
}

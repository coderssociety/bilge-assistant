import Testing
@testable import AsistanCore

@Suite("Mac control")
struct MacControlTests {
    @Test("recognizes Mac control phrases", arguments: [
        ("parlaklığı artır", QuickIntent.brightness(.up)),
        ("ekran parlaklığını azalt", .brightness(.down)),
        ("parlaklığı biraz kıs", .brightness(.down)),
        ("parlaklığı yüzde 50 yap", .brightness(.set(50))),
        ("parlaklığı yüzde elli yap", .brightness(.set(50))),
        ("parlaklığı 30'a getir", .brightness(.set(30))),
        ("parlaklığı yüzde 20 artır", .brightness(.change(20))),
        ("parlaklığı sonuna kadar aç", .brightness(.set(100))),
        ("ekranı parlat", .brightness(.up)),
        ("Bluetooth'u kapat", .bluetooth(.off)),
        ("bluetooth'u açar mısın", .bluetooth(.on)),
        ("Bluetooth açık mı", .bluetooth(.status)),
        ("rahatsız etme modunu aç", .system(.focusOn)),
        ("Rahatsız etmeyi kapat", .system(.focusOff)),
        ("odak modunu aç", .system(.focusOn)),
        ("bilgisayarı yeniden başlat", .system(.restart)),
        ("Mac'i yeniden başlat", .system(.restart)),
        ("Mac'i kapat", .system(.shutDown)),
        ("bilgisayarı kapatır mısın", .system(.shutDown)),
        ("oturumu kapat", .system(.logOut)),
    ])
    func recognized(text: String, expected: QuickIntent) {
        #expect(QuickIntentParser.parse(TurkishNumberParser.digitize(text)) == expected)
    }

    @Test("leaves other phrasings to the model", arguments: [
        "ekranı kapat", "Safari'yi kapat", "Bluetooth ayarlarını aç", "parlaklık nasıl ayarlanır",
        "uyku odağını aç", "bilgisayarı baştan başlat", "Mac'teki notları kapat",
    ])
    func deferred(text: String) {
        let intent = QuickIntentParser.parse(text)
        let controls: [QuickIntent?] = [.system(.shutDown), .system(.restart), .brightness(.up)]
        #expect(!controls.contains(intent))
        #expect(intent != .system(.focusOn))
    }

    @Test("reads Focus requests", arguments: [
        ("rahatsız etme modunu açar mısın lütfen", AssistantLanguage.turkish, true),
        ("odağı kapat", .turkish, false),
        ("uyku odağını aç", .turkish, true),
        ("turn on do not disturb", .english, true),
        ("turn off focus", .english, false),
        ("disable do not disturb", .english, false),
    ])
    func focus(text: String, language: AssistantLanguage, expected: Bool) {
        #expect(MacControlRequest.focus(text, language: language) == expected)
    }

    @Test("reads power requests", arguments: [
        ("bilgisayarı yeniden başlatır mısın", AssistantLanguage.turkish, MacControlRequest.Power?.some(.restart)),
        ("Mac'i tamamen kapat", .turkish, .shutDown),
        ("oturumdan çık", .turkish, .logOut),
        ("ekranı kapat", .turkish, nil),
        ("Mac'teki Safari'yi kapat", .turkish, nil),
        ("bilgisayardaki pencereyi kapat", .turkish, nil),
        ("restart my Mac", .english, .restart),
        ("shut down the computer", .english, .shutDown),
        ("log me out", .english, .logOut),
        ("restart the song", .english, nil),
        ("turn off the display", .english, nil),
    ])
    func power(text: String, language: AssistantLanguage, expected: MacControlRequest.Power?) {
        #expect(MacControlRequest.power(text, language: language) == expected)
    }

    @Test("reads brightness requests", arguments: [
        ("ekran parlaklığını artır", AssistantLanguage.turkish, MacControlRequest.Change?.some(.up(nil))),
        ("parlaklığı yüzde 20 azalt", .turkish, .down(20)),
        ("parlaklığı yarıya, yüzde 50'ye indir", .turkish, .set(50)),
        ("parlaklığı en yüksek yap", .turkish, .set(100)),
        ("ekranı biraz karart", .turkish, .down(nil)),
        ("make the screen brighter", .english, .up(nil)),
        ("dim the screen", .english, .down(nil)),
        ("set brightness to 40 percent", .english, .set(40)),
        ("brightness to max", .english, .set(100)),
    ])
    func brightness(text: String, language: AssistantLanguage, expected: MacControlRequest.Change?) {
        #expect(MacControlRequest.brightness(text, language: language) == expected)
    }

    @Test("reads Bluetooth requests", arguments: [
        ("bluetooth'u kapatır mısın", AssistantLanguage.turkish, MacControlRequest.Switch?.some(.off)),
        ("bluetooth'u aç", .turkish, .on),
        ("bluetooth açık mı", .turkish, .status),
        ("bluetooth durumu ne", .turkish, .status),
        ("turn bluetooth off", .english, .off),
        ("switch on bluetooth", .english, .on),
        ("is bluetooth on", .english, .status),
    ])
    func bluetooth(text: String, language: AssistantLanguage, expected: MacControlRequest.Switch?) {
        #expect(MacControlRequest.bluetooth(text, language: language) == expected)
    }
}

@Suite("FocusShortcut")
struct FocusShortcutTests {
    private let names = ["Sabah rutini", "Rahatsız Etme Aç", "Rahatsız Etme Kapat", "Uyku Odağı", "Eve geliyorum"]

    @Test("picks the shortcut for the direction asked", arguments: [
        ("rahatsız etme modunu aç", true, "Rahatsız Etme Aç"),
        ("rahatsız etmeyi kapat", false, "Rahatsız Etme Kapat"),
        ("uyku odağını aç", true, "Uyku Odağı"),
    ])
    func picks(command: String, turnOn: Bool, expected: String) {
        #expect(FocusShortcut.pick(from: names, turnOn: turnOn, command: command) == expected)
    }

    @Test("uses a toggle, and English names")
    func toggleAndEnglish() {
        #expect(FocusShortcut.pick(from: ["Toggle DND"], turnOn: false, command: "turn off do not disturb") == "Toggle DND")
        #expect(FocusShortcut.pick(from: ["Focus On", "Focus Off"], turnOn: false, command: "turn off focus") == "Focus Off")
    }

    @Test("finds nothing without a Focus shortcut or for the other direction only")
    func none() {
        #expect(FocusShortcut.pick(from: ["Sabah rutini", "Işıkları aç"], turnOn: true, command: "odak modunu aç") == nil)
        #expect(FocusShortcut.pick(from: ["Rahatsız Etme Aç"], turnOn: false, command: "rahatsız etmeyi kapat") == nil)
    }
}

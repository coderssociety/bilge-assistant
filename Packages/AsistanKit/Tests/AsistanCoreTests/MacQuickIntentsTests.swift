import Testing
@testable import AsistanCore

@Suite("Mac quick intents")
struct MacQuickIntentsTests {
    @Test("recognizes Mac controls", arguments: [
        ("ekran görüntüsü al", QuickIntent.screenshot),
        ("Wi-Fi'ı kapat", .wifi(on: false)),
        ("wifi aç", .wifi(on: true)),
        ("Wi-Fi'yi açar mısın", .wifi(on: true)),
        ("pencereyi küçült", .window(.minimize)),
        ("tam ekran yap", .window(.fullScreen)),
        ("pencereyi ekranın soluna al", .window(.leftHalf)),
        ("diğer uygulamaları gizle", .window(.hideOthers)),
        ("Bluetooth ayarlarını aç", .settings(.bluetooth)),
        ("yazılım güncelleme ayarlarını aç", .settings(.softwareUpdate)),
        ("bildirim ayarlarına git", .settings(.notifications)),
        ("diskte ne kadar yer kaldı", .systemInfo(.disk)),
        ("bilgisayar ne zamandır açık", .systemInfo(.uptime)),
        ("IP adresim ne", .systemInfo(.network)),
    ])
    func recognized(text: String, expected: QuickIntent) {
        #expect(QuickIntentParser.parse(text) == expected)
    }

    @Test("leaves anything with more content to the model", arguments: [
        "bu pencerenin ekran görüntüsünü panoya al", "Wi-Fi'ı kapat ve müziği aç", "küçült",
        "Safari'yi gizle", "ses ayarlarını kıs", "Telegram ayarlarını aç",
    ])
    func notRecognized(text: String) {
        #expect(QuickIntentParser.parse(text) == nil)
    }
}

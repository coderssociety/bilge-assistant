import Testing
@testable import AsistanCore

@Suite("RouteGuard info topics")
struct InfoTopicRoutingTests {
    @Test("questions go to the tool for their topic", arguments: [
        ("son depremler", "earthquakes"), ("deprem oldu mu", "earthquakes"), ("İzmir'de deprem var mı", "earthquakes"),
        ("bugün büyük deprem oldu mu", "earthquakes"), ("en son deprem nerede", "earthquakes"),
        ("Konya'da deprem oldu mu", "earthquakes"),
    ])
    func routes(command: String, expected: String) {
        #expect(RouteGuard.infoTopic(command) == expected)
    }

    @Test("nearby requests stay with other actions", arguments: [
        "deprem çantasına ne konur", "deprem sigortası nedir", "spor haberlerini oku", "Galatasaray haberleri",
        "Galatasaray kaç yılında kuruldu", "Galatasaray marşını çal", "İzmir'de hava nasıl", "dolar kaç lira",
        "THY bileti ne kadar", "borsa nedir", "Galatasaray maçını takvime ekle", "yarın maça gitmeyi hatırlat",
        "Konya'da hava nasıl", "nasılsın", "dünya haberleri",
    ])
    func staysAway(command: String) {
        #expect(RouteGuard.infoTopic(command) == nil)
    }

    @Test("English requests", arguments: [
        ("any earthquakes today", "earthquakes"), ("was there an earthquake near me", "earthquakes"),
    ])
    func english(command: String, expected: String) {
        #expect(RouteGuard.infoTopic(command, language: .english) == expected)
    }

    @Test("English requests for other actions", arguments: [
        "earthquake kit checklist", "read the sports news", "what's the weather in Izmir", "book a Turkish Airlines flight",
        "should I buy Aselsan stock",
    ])
    func englishStaysAway(command: String) {
        #expect(RouteGuard.infoTopic(command, language: .english) == nil)
    }
}

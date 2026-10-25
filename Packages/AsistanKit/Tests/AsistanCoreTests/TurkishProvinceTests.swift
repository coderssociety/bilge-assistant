import Testing
@testable import AsistanCore

@Suite("TurkishProvince")
struct TurkishProvinceTests {
    @Test("all 81 provinces with their plate codes")
    func table() {
        #expect(TurkishProvince.all.count == 81)
        #expect(Set(TurkishProvince.all.map(\.plate)) == Set(1...81))
        #expect(TurkishProvince.named("İstanbul")?.plate == 34)
        #expect(TurkishProvince.named("ankara")?.plate == 6)
        #expect(TurkishProvince.named("Düzce")?.plate == 81)
        #expect(TurkishProvince.named("Berlin") == nil)
    }

    @Test("found with Turkish case endings and old names", arguments: [
        ("İzmir'de motorin fiyatı", 35), ("Ankara'daki ezan vakitleri", 6), ("konya için benzin", 42),
        ("Kars'ta akşam ezanı", 36), ("Urfa'da iftar kaçta", 63), ("Antep'te benzin", 27), ("izmirde lpg", 35),
        ("istanbulun benzin fiyatı", 34), ("Afyon'da imsak", 3),
    ])
    func find(text: String, plate: Int) {
        #expect(TurkishProvince.find(in: text)?.plate == plate)
    }

    @Test("ordinary words are not provinces")
    func notProvinces() {
        #expect(TurkishProvince.find(in: "karşı komşunun benzin fiyatı") == nil)
        #expect(TurkishProvince.find(in: "benzin ne kadar") == nil)
    }

    @Test("the question particle is not Muş, the province with its endings is")
    func questionParticle() {
        #expect(TurkishProvince.find(in: "benzin fiyatını bulur musun") == nil)
        #expect(TurkishProvince.find(in: "akşam ezanı ne zaman biliyor musun") == nil)
        #expect(TurkishProvince.find(in: "motorin kaç lira söyler müsün") == nil)
        #expect(TurkishProvince.find(in: "Muş için namaz vakitleri")?.plate == 49)
        #expect(TurkishProvince.find(in: "Muş'ta benzin fiyatı")?.plate == 49)
        #expect(TurkishProvince.find(in: "Muş'un benzin fiyatını bulur musun")?.plate == 49)
        #expect(TurkishProvince.find(in: "muş akşam ezanı")?.plate == 49)
    }

    @Test("places outside Turkey said in a request")
    func spokenPlace() {
        #expect(SpokenPlace.name(in: "Berlin'de akşam ezanı kaçta", language: .turkish) == "Berlin")
        #expect(SpokenPlace.name(in: "Ramazan'da iftar kaçta", language: .turkish) == nil)
        #expect(SpokenPlace.name(in: "prayer times in New York", language: .english) == "New York")
        #expect(SpokenPlace.name(in: "prayer times for Friday", language: .english) == nil)
        #expect(SpokenPlace.name(in: "akşam ezanı kaçta", language: .turkish) == nil)
    }
}

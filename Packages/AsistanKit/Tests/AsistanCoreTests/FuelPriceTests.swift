import Foundation
import Testing
@testable import AsistanCore

@Suite("FuelPrice")
struct FuelPriceTests {
    @Test("reads the fuels asked for", arguments: [
        ("benzin ne kadar", [FuelKind.gasoline]),
        ("İzmir'de motorin fiyatı", [.diesel]),
        ("LPG kaç lira", [.lpg]),
        ("mazot kaça", [.diesel]),
        ("akaryakıt fiyatları", FuelKind.allCases),
        ("benzine zam geldi mi", [.gasoline]),
        ("benzin ve motorin kaç lira", [.gasoline, .diesel]),
    ])
    func turkishKinds(text: String, expected: [FuelKind]) {
        #expect(FuelQuestion.kinds(in: text, language: .turkish) == expected)
    }

    @Test("fuel words that are not price questions", arguments: [
        "benzin almayı hatırlat", "Google'da en yakın benzinlik", "araba ne kadar benzin yakıyor", "motorin listeme ekle",
        "benzin fiyatlarını Elif'e mesaj at",
    ])
    func notFuel(text: String) {
        #expect(FuelQuestion.kinds(in: text, language: .turkish) == nil)
    }

    @Test("English requests")
    func english() {
        #expect(FuelQuestion.kinds(in: "how much is diesel", language: .english) == [.diesel])
        #expect(FuelQuestion.kinds(in: "fuel prices in Izmir", language: .english) == FuelKind.allCases)
        #expect(FuelQuestion.kinds(in: "remind me to buy gas", language: .english) == nil)
    }

    @Test("Opet: the centre district's gasoline and standard diesel")
    func opet() {
        #expect(FuelPriceParser.opet(FuelFixtures.opetIzmir) == [.gasoline: 77.51, .diesel: 98.13])
        #expect(FuelPriceParser.opet(FuelFixtures.opetIstanbulAsia) == [.gasoline: 76.12, .diesel: 96.70])
        #expect(FuelPriceParser.opet(Data(#"{"errorMessage":"Kayıt bulunamadı."}"#.utf8)).isEmpty)
    }

    @Test("Petrol Ofisi: the province's row by plate code, with LPG")
    func petrolOfisi() {
        let page = FuelFixtures.petrolOfisi
        #expect(FuelPriceParser.petrolOfisi(page, plate: 35) == [.gasoline: 77.50, .diesel: 98.10, .lpg: 41.20])
        #expect(FuelPriceParser.petrolOfisi(page, plate: 34) == [.gasoline: 76.30, .diesel: 96.80, .lpg: 41.20])
        #expect(FuelPriceParser.petrolOfisi(page, plate: 6).isEmpty)
        #expect(FuelPriceParser.petrolOfisi("<html></html>", plate: 35).isEmpty)
    }

    @Test("spoken answers")
    func report() {
        let prices: [FuelKind: Double] = [.gasoline: 77.5, .diesel: 98.13]
        #expect(FuelReport.text(prices, kinds: [.diesel], province: "İzmir", language: .turkish) == "İzmir'de litre fiyatı motorin 98,13 lira.")
        #expect(FuelReport.text(prices, kinds: FuelKind.allCases, province: "İzmir", language: .turkish)
            == "İzmir'de litre fiyatı benzin 77,50 ve motorin 98,13 lira. LPG fiyatını bulamadım.")
        #expect(FuelReport.text(prices, kinds: [.gasoline, .diesel], province: "Izmir", language: .english)
            == "In Izmir, gasoline 77.50 and diesel 98.13 lira per litre.")
        #expect(FuelReport.text(prices, kinds: [.lpg], province: "İzmir", language: .turkish) == nil)
    }
}

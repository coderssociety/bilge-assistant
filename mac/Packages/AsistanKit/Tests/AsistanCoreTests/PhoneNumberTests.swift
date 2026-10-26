import Testing
@testable import AsistanCore

@Suite("PhoneNumber")
struct PhoneNumberTests {
    @Test("normalizes Turkish and international formats", arguments: [
        ("0532 123 45 67", "+905321234567"), ("+90 (532) 123-45-67", "+905321234567"), ("532 123 4567", "+905321234567"),
        ("0090 532 123 45 67", "+905321234567"), ("+44 20 7946 0958", "+442079460958"),
    ])
    func normalized(text: String, expected: String) {
        #expect(PhoneNumber.normalized(text) == expected)
    }

    @Test("rejects non-numbers", arguments: ["ahmet@example.com", "123", "abc 0532"])
    func rejected(text: String) {
        #expect(PhoneNumber.normalized(text) == nil)
    }
}
